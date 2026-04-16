function varargout = prepcta(input, kwargs)
    %% Preparing CTA measurements: calculate spectra (PSD), perform cross-correlation correction.

    %% Examples:
    %% 1. Load cta measurements, calculate auto-spectra (struct notation):
    % data = loadcta('C:\Users\morle\Desktop\swept_plate\01_02_24\240201_175931');
    % dataprep = prepcta(p1, output = 'struct');

    %% 2. Load cta measurements, calculate auto-spectra (array notation):
    % [scan, data, raw] = loadcta('C:\Users\morle\Desktop\swept_plate\01_02_24\240201_175931', output = 'array');
    % [spec, f, vel, x, y, z] = prepcta(raw, scan = scan);

    arguments
        %% input
        input {mustBeA(input, {'double', 'struct'})}
        kwargs.scan (:,:) double = [] % scan table
        kwargs.storeraw (1,1) logical = false
        kwargs.type (1,:) char {mustBeMember(kwargs.type, {'wire', 'film'})} = 'wire'
        %% spectra
        kwargs.spectrumtype (1,:) char {mustBeMember(kwargs.spectrumtype, {'power', 'psd'})} = 'psd'
        kwargs.freqrange (1,:) char {mustBeMember(kwargs.freqrange, {'onesided', 'twosided', 'centered'})} = 'onesided' % half, total and total centered spectra
        kwargs.winfun (1,:) char {mustBeMember(kwargs.winfun, {'uniform', 'hanning', 'hamming'})} = 'hanning' % window function
        kwargs.winfuncor (1,1) logical = true % spectra power correction at weighting data by window function
        kwargs.winlen double = 4096 % FFT window length
        kwargs.overlap double = 3072 % FFT window overlay
        kwargs.offset (1,:) {mustBeA(kwargs.offset, {'double', 'cell '})} = 0 % sliding window offset at performing STFT
        kwargs.center (1,1) logical = true % normalize data
        kwargs.fs (1,1) double = 25e3 % frequency sampling
        kwargs.norm (1,:) char {mustBeMember(kwargs.norm, {'none', 'rms'})} = 'rms' % spectra norm, `rms` means assertion sqrt(sum(spec))=rms(x)
        kwargs.corvibr (1,1) logical = true; % suppress vibrations by cross-spectra technique
        kwargs.corvibrdev (1,1) logical = false; % suppress vibrations by cross-correlation technique
        kwargs.corvibrind (1,:) double = [1, 2] % indexes of correcting channel and reference channel
        kwargs.procamp (1,:) char {mustBeMember(kwargs.procamp, {'rms', 'sum', 'sel'})} = 'rms'
        kwargs.procspec (1,:) char {mustBeMember(kwargs.procspec, {'spectrogram', 'manual'})} = 'spectrogram'
        kwargs.poolsize (1,:) double = 2
        %% organization
        kwargs.reshape double = [] % reshape data
        kwargs.permute double = [] % permute data
        %% transform
        kwargs.unit (1,:) char {mustBeMember(kwargs.unit, {'mm', 'count'})} = 'mm' % scan unit
        kwargs.refmarker (1,:) char {mustBeMember(kwargs.refmarker, {'none', 'n2', 'n6', 'n8', 'n9'})} = 'none' % reference marker of skew coordinate system
        kwargs.xfit = [] % fitobj transfrom to leading edge coordinate system
        kwargs.yfit = [] % fitobj to reverse a correction of vectical scanning component
        kwargs.zfit = [] % fitobj transfrom to leading edge coordinate system
        kwargs.steps (1,:) double = [50, 800, 400] % single step displacement of step motor in um (x,y,z)
        kwargs.label (1,:) char = []
        kwargs.ort (:,2) double = [] %% LE coordinate system reference points
        kwargs.skew (:,2) double = [] %% skew coordinate system reference points
    end

    % parse inputs
    if isa(input, 'double')
        kwargs.raw = input;
    else
        if isfield(input, 'raw'); kwargs.raw = input.raw; end
        if isfield(input, 'scan'); kwargs.scan = input.scan; end
        if isfield(input, 'fs'); kwargs.fs = input.fs; end
        if isfield(input, 'reshape'); kwargs.reshape = input.reshape; end
        if isfield(input, 'permute'); kwargs.permute = input.permute; end
        if isfield(input, 'corvibrind'); kwargs.corvibrind = input.corvibrind; end
        if isfield(input, 'label'); kwargs.label = input.label; end
        if isfield(input, 'voltcal'); kwargs.voltcal = input.voltcal; else; kwargs.voltcal = []; end
        if isfield(input, 'velcal'); kwargs.velcal = input.velcal; else; kwargs.velcal = []; end
        if isfield(input, 'refmarker'); kwargs.refmarker = input.refmarker; end
        if isfield(input, 'xfit'); kwargs.xfit = input.xfit; end
        if isfield(input, 'yfit'); kwargs.yfit = input.yfit; end
        if isfield(input, 'zfit'); kwargs.zfit = input.zfit; end
        if isfield(input, 'ort'); kwargs.ort = input.ort; end
        if isfield(input, 'skew'); kwargs.skew = input.skew; end
        if isfield(input, 'step'); kwargs.step = input.step; end
    end

    % handler to select mask index by given frequency range
    freq2ind = @(f,x) find(f>=x(1)&f<=x(2));

    switch kwargs.type
        case 'wire'
            
            % to correct correrlated signal part
            if kwargs.corvibrdev
                u = squeeze(kwargs.raw(:,kwargs.corvibrind(1),:));
                v = squeeze(kwargs.raw(:,kwargs.corvibrind(2),:));
                Ruv = nonlinfilt(@(x, y, ~) x.*y, u, v, kernel = [kwargs.winlen, nan], stride = [kwargs.winlen, 1], ...
                    padval = {{'symmetric', false}, {'symmetric', false}});
                Ruv = mean(Ruv, 3);
                du = nonlinfilt(@(v, Ruv, ~) conv(normalize(v, 1, 'center'), Ruv, 'same'), v, Ruv, kernel = [nan, 1], padval = false);
                u = u - du;
                kwargs.raw(:,kwargs.corvibrind(1),:) = u;
            end

            % calculate auto/scross spectra
            switch kwargs.procspec
                case 'spectrogram'
                    [spec, f] = procspec(kwargs.raw, winfun = kwargs.winfun, winlen = kwargs.winlen, ...
                        overlap = kwargs.overlap, fs = kwargs.fs, norm = kwargs.norm, ...
                        spectrumtype = kwargs.spectrumtype, freqrange = kwargs.freqrange);
                case 'manual'
                    [spec, f] = procspecn(kwargs.raw, winfun = kwargs.winfun, winlen = kwargs.winlen, ...
                        overlap = kwargs.overlap, fs = kwargs.fs, ftdim = 1, chdim = 2, ans = 'cell', ...
                        norm = true, center = kwargs.center, offset = kwargs.offset, poolsize = kwargs.poolsize, avg = true);
            end
            df = f(2)-f(1);

            % to substract correrlated signal part 
            if kwargs.corvibr
                spec{kwargs.corvibrind(1),kwargs.corvibrind(1)} = spec{kwargs.corvibrind(1),kwargs.corvibrind(1)} ...
                    - abs(spec{kwargs.corvibrind(1),kwargs.corvibrind(2)}).^2./spec{kwargs.corvibrind(2),kwargs.corvibrind(2)};
            end
        
            % extract scanning points
            if ~isempty(kwargs.scan)
                x = squeeze(kwargs.scan(:,1,:));
                z = squeeze(kwargs.scan(:,2,:));
                y = squeeze(kwargs.scan(:,3,:));
                vm = kwargs.scan(:, 4);
            end
        
            % tranform y-axis to uncorrected vertical positions
            if ~isempty(kwargs.yfit) && ~isempty(kwargs.scan)
                y = y - round(kwargs.yfit(x, z)); 
            end
                
            % reshape spectra, scanning points and velocity
            if ~isempty(kwargs.reshape)
                for i = 1:size(spec, 1)
                    for j = 1:size(spec, 2)
                        spec{i,j} = reshape(spec{i,j}, [numel(f), kwargs.reshape]);
                    end
                end
                if ~isempty(kwargs.scan)
                    x = reshape(x, kwargs.reshape);
                    z = reshape(z, kwargs.reshape);
                    y = reshape(y, kwargs.reshape);
                    vm = reshape(vm, kwargs.reshape);
                end
                if kwargs.storeraw
                    kwargs.raw = reshape(kwargs.raw, [size(kwargs.raw, 1:2), kwargs.reshape]);
                    if isempty(kwargs.permute); kwargs.raw = permute(kwargs.raw, [3:ndims(kwargs.raw), 1:2]); end
                end
            end
            
            % permute spectra, scanning points and velocity
            if ~isempty(kwargs.permute)
                for i = 1:size(spec, 1)
                    for j = i:size(spec, 2)
                        spec{i,j} = permute(spec{i,j}, [1, kwargs.permute+1]);
                    end
                end
                if ~isempty(kwargs.scan)
                    vm = permute(vm, kwargs.permute);
                    x = permute(x, kwargs.permute);
                    y = permute(y, kwargs.permute);
                    z = permute(z, kwargs.permute);
                end
                if kwargs.storeraw; kwargs.raw = permute(kwargs.raw, [1:2, kwargs.permute + 2]); end
            end

            % transform units
            if ~isempty(kwargs.scan)
                switch kwargs.unit
                    case 'mm'
                        y = y/kwargs.steps(2);
                        if kwargs.refmarker ~= "none"
                            % legacy markers
                            switch kwargs.refmarker
                                case 'n2'
                                    kwargs.ort = [113.9, 63.7; 113.9, 112.4; 126.8, 118.9; 126.7, 70.2]; % mm
                                    kwargs.skew = [0, 0; 0, 2e4; 300, 2e4; 300, 0]; % count
                                case 'n6'
                                    kwargs.ort = [294.65, 147.38; 295.01, 171.91; 384.42, 214.55; 383.99, 189.59]; % count
                                    kwargs.skew = [0, 0; 6, 9850; 2040, 9500; 2030, -580]; % mm
                                case 'n8'
                                    kwargs.ort = [384.6, 189.4; 294, 148.4; 294.4, 198.5; 384.6, 139.4]; % mm
                                    kwargs.skew = [0, 0; -2086, 1060; -2086, 21124; 0, -20060]; % count
                                case 'n9'
                                    kwargs.ort = [429.76, 209.95; 429.43, 260.50; 474.0, 283.03; 474.0, 233.36]; % mm
                                    kwargs.skew = [0, 0; 0, 2e4; 1e3, 2e4; 1e3, 0]; % count
                            end
                        end

                        if ~isempty(kwargs.skew) && ~isempty(kwargs.ort)
                            % fit 
                            [xf,yf,zf] = prepareSurfaceData(kwargs.skew(:,1),kwargs.skew(:,2),kwargs.ort(:,1));
                            kwargs.xfit = fit([xf,yf],zf,'poly11');
                            [xf,yf,zf] = prepareSurfaceData(kwargs.skew(:,1),kwargs.skew(:,2),kwargs.ort(:,2));
                            kwargs.zfit = fit([xf,yf],zf,'poly11');
                        end

                        % transform to LE coordinate system
                        if ~isempty(kwargs.xfit); xtemp = kwargs.xfit(x,z); else; xtemp = x/kwargs.steps(1); end
                        if ~isempty(kwargs.zfit); ztemp = kwargs.zfit(x,z); else; ztemp = z/kwargs.steps(3); end
                        x = xtemp;
                        z = ztemp;
                end
            end
        
            % parse outputs
            result.spec = spec;
            result.f = f;
            if ismatrix(spec{1,1})
                switch kwargs.procamp
                    case 'rms'
                        handler = @(spec, freq) sqrt(abs(df*sum(spec(freq2ind(f,freq), :), 1)));
                    case 'sum'
                        handler = @(spec, freq) (df*sum(spec(freq2ind(f,freq), :), 1));
                    case 'sel'
                        @(spec, freq) spec(freq2ind(f,freq), :);
                end
            else
                switch kwargs.procamp
                    case 'rms'
                        handler = @(spec, freq) reshape(sqrt(abs(df*sum(spec(freq2ind(f,freq), :), 1))), size(spec, 2:ndims(spec)));
                    case 'sum'
                        handler = @(spec, freq) reshape(df*sum(spec(freq2ind(f,freq), :), 1), size(spec, 2:ndims(spec)));
                    case 'sel'
                        handler = @(spec, freq) reshape(spec(freq2ind(f,freq), :), [numel(freq2ind(f,freq)), size(spec, 2:ndims(spec))]);
                end
            end
            result.intspec = handler;
            result.freq2ind = freq2ind;
            if ~isempty(kwargs.scan)
                result.vm = vm;
                result.x = x;
                result.y = y;
                result.z = z;
            end
            if ~isempty(kwargs.label); result.label = kwargs.label; end
            if ~isempty(kwargs.voltcal); result.cal = kwargs.voltcal; end
            if ~isempty(kwargs.velcal); result.velcal = kwargs.velcal; end
            if kwargs.storeraw; result.raw = kwargs.raw; end
            varargout{1} = result;

        case 'film'
            % calculate auto/cross spectra
            result = struct;
            [spec, f] = procspec(kwargs.raw, winfun = kwargs.winfun, winlen = kwargs.winlen, ...
                overlap = kwargs.overlap, fs = kwargs.fs, norm = kwargs.norm, ans = 'double');
            df = f(2)-f(1);

            if ismatrix(spec)
                switch kwargs.procamp
                    case 'rms'
                        handler = @(spec, freq) sqrt(abs(df*sum(spec(freq2ind(freq), :))));
                    case 'sum'
                        handler = @(spec, freq) (df*sum(spec(freq2ind(freq), :)));
                    case 'sel'
                        @(spec, freq) spec(freq2ind(f,freq), :);
                end
            else
                switch kwargs.procamp
                    case 'rms'
                        handler = @(spec, freq) reshape(sqrt(abs(df*sum(spec(freq2ind(f,freq), :), 1))), size(spec, 2:ndims(spec)));
                    case 'sum'
                        handler = @(spec, freq) reshape(df*sum(spec(freq2ind(f,freq), :), 1), size(spec, 2:ndims(spec)));
                    case 'sel'
                        handler = @(spec, freq) reshape(spec(freq2ind(f,freq), :), [numel(freq2ind(f,freq)), size(spec, 2:ndims(spec))]);
                end
            end

            result.spec = spec;
            result.f = f;
            result.intspec = handler;
            result.freq2ind = freq2ind;
            if ~isempty(kwargs.label); result.label = kwargs.label; end
            if kwargs.storeraw; result.raw = kwargs.raw; end
            varargout{1} = result;
    end

end