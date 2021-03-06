clear;
maxiter=4;


IEEE118bus;
ptdf_matrix %Generation Shift Factor/Power Transfer Distribution Matrix


%Generator Bus Connection Matrix
Ag=zeros(nb,ng);
for i=1:nb
    for j=1:ng
        if gendata(j,1)==i
            Ag(i,j)=1;
        end
    end
end

%Setting up Matrices for the Quadratic Programming Solver
f=gencostdata(:,6)';%Cost function to minimize

for iter=1:maxiter

%Loss Factor Script
if iter~=1
lossfactor;
end

%Matrix Dimension gets too big
%Aeq=zeros(1,nb);
%for i=1:nb
%    for j=1:length(gendata(:,1))
%    if i==gendata(j,1)
%        Aeq(i)=1;
%    end
%    end
%end

if iter~=1
Aeq=ones(1,length(gendata(:,1))).*DF';                               %Generation Side of Pg=Pd Equation with Delivery Factor
beq=((DF'*busdata(:,3)));                   %Demand Side of Pg=Pd Equation with Delivery Factor
beq=beq-Ptotalloss;                         %Demand Side of Pg=Pd Equation + Losses
else
Aeq=ones(1,length(gendata(:,1)));           %1st Iteration without DF
beq=sum(busdata(:,3));                      %1st Iteration without DF
end

%Setting up Matrices for PTDF Formulation
A1=PTDF*Ag;    
pd=busdata(:,3);
if iter~=1
b1=prat(1:length(branchdata(:,1)))+PTDF*(pd-E);
b2=prat(1:length(branchdata(:,1)))-PTDF*(pd-E);
else
b1=prat(1:length(branchdata(:,1)))+PTDF*(pd);
b2=prat(1:length(branchdata(:,1)))-PTDF*(pd);
end
A=[A1; -A1];
b=[b1;b2];

%Generation limit for each generator
lb=gendata(:,10);
ub=gendata(:,9);

%Quadratic cost functions for each generator
Qmatrix=zeros(size(A,2),size(A,2));
for i=1:length(gencostdata(:,5))
    if gencostdata(i,5)~=0
        Qmatrix(i,i)=gencostdata(i,5);
    end
end

%Quadratic Programming with Gurobi Solver
names={num2str(zeros(1,length(gendata(:,1))))};
for i=1:length(gendata(:,1))
names(i) = {num2str("P"+num2str(i))};
end
model.varnames = names;
model.obj = f; 
model.Q = sparse(Qmatrix);
model.A = [sparse(A); sparse(Aeq)]; % A must be sparse
model.sense = [repmat('<',size(A,1),1); repmat('=',size(Aeq,1),1)];
model.rhs = full([b(:); beq(:)]); % rhs must be dense
if ~isempty(lb)
    model.lb = lb;
else
    model.lb = -inf(size(model.A,2),1); % default lb for MATLAB is -inf
end
if ~isempty(ub)
    model.ub = ub;
end

gurobi_write(model, 'DCOPF_QP.lp');

results = gurobi(model);
lambda.lower = max(0,results.rc);
lambda.upper = -min(0,results.rc);
lambda.ineqlin = -results.pi(1:size(A,1));
lambda.eqlin = results.pi((size(A,1)+1):end);


%Generation Cost, Congestion Cost and Powerflow
generationcost=lambda.eqlin;
congestioncost=(lambda.ineqlin'*[-PTDF ; PTDF])';
lmp=generationcost+congestioncost;
lineflow=PTDF*(Ag*results.x-pd);
if iter~=1
losscost=lambda.eqlin*(DF-1);
end
end



%Printing out the Solution
for v=1:length(names)
fprintf('\n %s = %2.2f MW\n', names{v}, results.x(v));
end

for v=1:length(generationcost)
fprintf('\n Generation cost = %g $/MWh\n\n', generationcost);
end

busnumber=busdata(:,1);

for v=1:length(congestioncost)
    if congestioncost(v)~=0
    fprintf(' Congestion Cost @ Bus %g = %4.2f $/MWh\n', busnumber(v) , congestioncost(v));
    end
end

fprintf('\n\n   LMP -- Bus Number ||    Generation Cost ||  Congestion Cost \n \n')
for v=1:length(lmp)
        if lmp(v)~=0
         fprintf(' The LMP @ Bus %2.4g is %4.2f $/MWh generation cost and %4.2f $/MWh congestion cost\n', busnumber(v) , generationcost, congestioncost(v));
        end
end


fprintf('\n              Line flow Table \n')
fprintf('   From Bus  ||    To Bus   ||   Line Flow \n\n')
for v=1:length(lineflow)
        fprintf('%8.0f     ||%8.0f     ||%13.6f MW  \n', fb(v) , tb(v) , lineflow(v));
end

fprintf('\n The objective value is %4.2f $/h\n', results.objval);
