%% test: cfic
%% initialize instance
try; delete(c); catch; end; close all; clc; clear;
c = cfic();
disp(c)
%% configure function handler
c.process = @process;
%% initialize lcard
c.lcard.initialize();
%% confiugre ADC
c.lcard.adcconf('channel',true(1,32),'gain',repelem(1,32),'difm',true(1,32),...
    'mask',1:32,'offset',repelem(0,32),'scale',repelem(1,32),'rate',4,...
    'dquser',c.dq.batch,'pause',2)
%% single read ADC
data = c.lcard.adcread();
%% confiugre MCU
c.mcu.set(struct(adc_offset=1500,dac=struct(index=0:31,value=1.2*ones(1,32)),echo=true));
%% get data MCU
c.mcu.get();
%% start async loop ADC read
c.lcard.asyncadcread(true,'pause',2)
%% stop async loop ADC read
c.lcard.asyncadcread(false)
%% optimization `interior-point`
problem = struct;
index = 0:2;
problem.x0 = ones(1,numel(index));
problem.lb = -2*ones(1,numel(index));
problem.ub = 2*ones(1,numel(index));
problem.options = optimoptions('fmincon','Algorithm','interior-point',...
    'MaxFunctionEvaluations',2e3,'MaxIterations',2e3,'DiffMinChange',0.05,...
    'DiffMaxChange',0.2,'StepTolerance',0.01,'FunctionTolerance',1e-3);
% start
c.optimize(problem,index,parallel=false)
%% optimization `ga`
problem = struct;
index = 0:2;
problem.x0 = ones(1,numel(index));
problem.lb = -2*ones(1,numel(index));
problem.ub = 2*ones(1,numel(index));
problem.options = optimoptions('ga');
% start
c.optimize(problem,index)
%% terminate optimization
cancel(c.ff.optimize)
%% reference
%% interior-point
% http://127.0.0.1:64437/static/help/optim/ug/tolerances-and-stopping-criteria.html
% http://127.0.0.1:64437/static/help/optim/ug/tolerance-details.html
% http://127.0.0.1:64437/static/help/optim/ug/iterations-and-function-counts.html
% http://127.0.0.1:64437/static/help/optim/ug/optimization-options-reference.html
%% ga
% http://127.0.0.1:64437/static/help/gads/ga.html#mw_4a8bfdb9-7c4c-4302-8f47-d260b7a43e26
%%