%% test: lcard
%% clear instance
clc; close all; try; delete(l); catch; end
%%
l = lcard();
%% initialize device
l.initialize();
%% configure ADC
l.adcconf('channel',true(1,32),'gain',repelem(0,32),...
    'difm',true(1,32),'rate',4,'pause',2)
%% release device
l.release();
%% start async file reading
l.asyncfileread(pwd)
%% stop async file reading
cancel(l.ff.asyncfileread)
%% read ADC
data = l.adcread();
%% start async loop ADC read
l.asyncadcread(true,pause=2.5)
%% stop async loop ADC read
l.asyncadcread(false)
%%
l.release();
%%
l.initialize()
%% reference
% http://127.0.0.1:53926/static/help/matlab/use-prebuilt-matlab-interface-to-c-library.html
% http://127.0.0.1:53926/static/help/matlab/matlab_external/pass-struct-parameter.html
