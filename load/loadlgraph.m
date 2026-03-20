function result = loadlgraph(folder,options)
    arguments (Input)
        folder {mustBeFolder}
        options.range (1,1) double = 20 % ADC ragne
        options.resolution (1,1) double = 14 % ADC resolution
    end
    arguments (Output)
        result (1,1) struct
    end

dpar = dir(fullfile(folder,'*.par'));
ddat = dir(fullfile(folder,'*.dat'));
h = @(d)arrayfun(@(x)string(fullfile(x.folder,x.name)),d);

fpar = h(dpar); fdat = h(ddat);
% load
dat = arrayfun(@(f)lgraphReadData(f),fdat,'UniformOutput',false);
par = arrayfun(@(f)lgraphReadParam(f),fpar,'UniformOutput',false);
% modify
par = cellfun(@(p)setfield(p,'ActiveAdcChannelArray',logical(p.ActiveAdcChannelArray)),par,'UniformOutput',false);
% reshape
dat = cellfun(@(d,p)reshape(d,p.RealChannelsQuantity,[]),dat,par,'UniformOutput',false);
% convert to voltage
dat = cellfun(@(d,p)options.range.*d./(2.^options.resolution)./double(2.^(2.*p.AdcGainArray(p.ActiveAdcChannelArray))),dat,par,'UniformOutput',false);
% apply calibration
dat = cellfun(@(d,p)p.AdcScale(p.ActiveAdcChannelArray).*d+p.AdcOffset(p.ActiveAdcChannelArray),dat,par,'UniformOutput',false);
% save
result = struct;
fs = unique(cellfun(@(p)p.AdcRate*1e3,par));
% concatenete data
try
    dat = cat(ndims(dat{1})+1,dat{:});
catch
end
result.data = dat;
result.fs = fs;
result.filename = fdat;
end