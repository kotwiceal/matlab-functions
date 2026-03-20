%% test: mcu
clf; close all;
m = mcu();
disp(m)
%% HTTP GET
data = m.get();
disp(data)
%% HTTP POST
data = struct(adc_offset=1500,dac=struct(index=0:31,value=1.2*ones(1,32)),echo=true);
m.set(data)
%%