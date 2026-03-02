%% test: cfic
%% initialize instance
try; delete(c); catch; end; close all; clc; clear;
c = cfic("C:\Users\lab21_3\Documents\MATLAB\lcard_data_test\");
disp(c)
%% receive MCU parameters, show dashboard
d = c.mcu_get();
disp(d)
%% transmit parameter to MCU 
c.mcu_set(struct(adc_offset=1000,dac=struct(index=0:31,value=150*ones(1,32))));
%% start loop asynchronous file reading 
c.asyncfileread(true,rmdir=false,test=true)
%% stop loop asynchronous file reading
c.asyncfileread(false)
%% test: optimization
% define problem
problem = struct;
index = 0:2;
problem.x0 = ones(1,numel(index));
problem.lb = -2*ones(1,numel(index));
problem.ub = 2*ones(1,numel(index));
problem.options = optimoptions('fmincon','Algorithm','interior-point','MaxFunctionEvaluations',2,'MaxIterations',2);
% start
c.optimize(problem,index)
%%