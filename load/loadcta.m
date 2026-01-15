function varargout = loadcta(path, kwargs)
    %% Import hot-wire data from specified folder with/without subfolders.

    arguments
        path (1,:) {mustBeA(path, {'char', 'string'})}
        kwargs.vendor (1,:) char {mustBeMember(kwargs.vendor, {'labview', 'lcard'})} = 'labview' % specify data import algorithm for vendor software export format
        %% labview settigns
        kwargs.subfolders (1,1) logical = false
        kwargs.datadelimiter (1,:) char = '\t'
        kwargs.scandelimiter (1,:) char = '\t'
        kwargs.rawdelimiter (1,:) char = '\t'
        kwargs.dataseparator (1,:) char = '.'
        kwargs.scanseparator (1,:) char = ','
        kwargs.rawseparator (1,:) char = ','
        kwargs.rawextension (1,:) char = '.dat'
        kwargs.rawtype (1,:) char {mustBeMember(kwargs.rawtype, {'ascii', 'bin'})} = 'bin'
        kwargs.numch (1,1) double = 2
        kwargs.calib (1,1) logical = true
        kwargs.castraw {mustBeMember(kwargs.castraw, {'single', 'double'})} = 'double'
        %% lcard settings
        kwargs.RealChannelsQuantity (1,1) double = 16
        kwargs.fs (1,1) double = 25e3
        kwargs.DataCalibrScale (1,:) double = 0.00125*ones(1,16)
        kwargs.DataCalibrZeroK (1,:) double = zeros(1,16)
        kwargs.DataCalibrOffset (1,:) double = zeros(1,16)
    end

    warning on

    scan = []; data = []; raw = []; voltcal = []; velcal = [];

    switch kwargs.vendor
        case 'labview'
            % get filenames
            filenames.dat = arrayfun(@(d)string(fullfile(d.folder,d.name)),dir(fullfile(path,'*.dat')));
            filenames.txt = arrayfun(@(d)string(fullfile(d.folder,d.name)),dir(fullfile(path,'*.txt')));
            try; filenames.raw = filenames.dat(contains(filenames.dat, 'raw')); catch; warning('raw data not found'); end
            try; filenames.data = filenames.dat(~contains(filenames.dat, 'raw')); catch; warning('spectra data not found'); end
            try; filenames.scan = filenames.txt(contains(filenames.txt, 'scan')); catch; warning('scan data not found'); end
            try; filenames.cal = filenames.txt(contains(filenames.txt, 'cal')); catch; warning('calibration data not found'); end
        
            % load spectra
            try
                for i = 1:numel(filenames.data)
                    data = cat(3, data, table2array(readtable(filenames.data(i), 'Delimiter', kwargs.datadelimiter, 'DecimalSeparator', kwargs.dataseparator))); 
                end
                data = reshape(data, [size(data, 1:2), size(filenames.data)]);
            catch
                warning("data loading failed")
            end
        
            % load raw
            try
                switch kwargs.rawtype
                    case 'ascii'
                        for i = 1:numel(filenames.raw)
                            temporary = readtable(filenames.raw(i), 'Delimiter', kwargs.rawdelimiter, 'DecimalSeparator', kwargs.rawseparator, ...
                                'VariableNamingRule', 'preserve');
                            try
                                temporary = table2array(temporary(5:end, 2:end));
                            catch
                                temporary = nan([size(raw,1), 3]);
                            end
                            raw = cat(2, raw, temporary); 
                        end
                        chsz = size(temporary, 2);
                        raw = reshape(raw, [size(raw, 1), chsz, size(filenames.raw)]);
                    case 'bin'
                        raw = cell(numel(filenames.raw),1);
                        for i = 1:numel(raw)
                            id = fopen(filenames.raw(i),'r');
                            raw{i} = cast(fread(id,'int16','b'),'int16');
                            fclose(id);
                        end
                        raw = cellfun(@(x)x(5:end),raw,'UniformOutput',false);
                        raw = cellfun(@(x)reshape(x,kwargs.numch,[])',raw,'UniformOutput',false);
                        raw = cell2mat(shiftdim(raw,-ndims(raw{1})));
                        raw = cast(raw,kwargs.castraw);
                end
            catch
                warning("raw loading failed")
            end
                
            % load scan
            try
                for i = 1:numel(filenames.scan)
                    scan = cat(3, scan, table2array(readtable(filenames.scan(i), 'Delimiter', kwargs.scandelimiter, 'DecimalSeparator', kwargs.scanseparator))); 
                end
            catch 
                warning("scan loading failed")
            end
            
            % load cal
            try
                mes = "calibration loading failed";
                if ~isempty(filenames.cal) && kwargs.calib
                    temporary = readtable(filenames.cal, 'Delimiter', 'tab', 'VariableNamingRule', 'Preserve');
                    voltmap = table2array(temporary(1:3,1:2));
                    coef = table2array(temporary(6,:));
        
                    mes = "calibration applying failed";
                    % convert to voltage
                    sz = size(raw); if ismatrix(raw); sz(3) = 1; end
                    raw = permute(permute(raw,[2, 1, 3]).*voltmap(1:sz(2),2)+voltmap(1:sz(2),1), [2, 1, 3]);
        
                    % convert to velocity
                    eccor = ((coef(5)-coef(4))./(coef(5)-scan(:,10))).^0.5;
                    raw(:,1,:) = permute(coef(1)*((squeeze(raw(:,1,:)).*eccor').^2-coef(3)).^coef(2), [1, 3, 2]);
                    raw = real(raw);

                    voltcal = @(x,ch) voltmap(ch,1)+x.*voltmap(ch,2);
                    velcal = @(vel,tempind) real(coef(1)*((vel.*eccor(tempind)').^2-coef(3)).^coef(2));
                end
            catch
                warning(mes);
            end
        
            % return
            result = struct();
            if ~isempty(scan); result.scan = scan; end
            if ~isempty(data); result.data = data; end
            if ~isempty(raw); result.raw = raw; end
            if ~isempty(voltcal); result.voltcal = voltcal; end
            if ~isempty(velcal); result.velcal = velcal; end
            varargout{1} = result;
            
        case 'lcard'
            % validation
            if isa(path, 'char'); path = string(path); end
            if isfolder(path)
                filenames.dat = getfilenames(path, extension = '.dat', subfolders = kwargs.subfolders);
            else
                filenames.dat = path;
            end

            % files loop
            for i = 1:numel(filenames.dat)
                % read data
                fid = fopen(filenames.dat(i), 'r');
                fseek(fid, 0, -1);
                data = fread(fid, 'int16');
                fclose(fid);
                data = reshape(data, kwargs.RealChannelsQuantity, []);
                % apply calibration
                data = (data+kwargs.DataCalibrZeroK').*kwargs.DataCalibrScale'+kwargs.DataCalibrOffset';
                % stack data
                raw = cat(3, raw, data');
            end
            result = struct(raw = raw, fs = kwargs.fs);
            varargout{1} = result;

    end
  
end