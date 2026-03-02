function data = lgraphReadPar(filename)
arguments (Input)
    filename {mustBeFile}
end
arguments (Output)
    data struct
end

% see https://www.lcard.ru/download/lgraph2_help.pdf, P.103

params = {
    {'Code', 20, '*char'}
    {'PlataNme', 17, '*char'}
    {'TimeString', 26, '*char'}
    {'ChannelsMax', 1, '*int16'}
    {'RealChannelsQuantity', 1, '*int16'}
    {'RealKadrsQuantity', 1, '*int32'}
    {'RealSamplesQuantity', 1, '*int32'}
    {'TotalTime', 1, '*double'}
    {'AdcRate', 1, '*float'}
    {'InterkadrDelay', 1, '*float'}
    {'ChannelRate', 1, '*float'}
    {'ActiveAdcChannelArray', 32, '*uint8'}
    {'AdcChannelArray', 32 '*uint8'}
    {'AdcGainArray', 32 '*uint8'}
    {'IsSignalArray', 32 '*uint8'}
    {'DataFormat', 1, '*int32'}
    {'RealKadrs64', 1, '*int64'}
    {'AdcOffset', 32, '*double'}
    {'AdcScale', 32, '*double'}
    {'CalibrScale', 1024, '*double'}
    {'CalibrOffset', 1024, '*double'}
    {'Segments', 1, '*int32'}
};

fields = cellfun(@(x)x{1},params,'UniformOutput',false);

f = fopen(filename);
data = cellfun(@(x)fread(f,x{2},x{3}),params,'UniformOutput',false);
data = cell2struct(data,fields);
fclose(f);

end