function data = loadpivdev(source, kwargs)
    arguments
        source {mustBeA(source, {'char', 'string', 'cell'})}
        kwargs.pattern {mustBeA(kwargs.pattern, {'char', 'string'})} = '*.vc7'
        kwargs.subfolders (1,1) logical = false
        kwargs.parallel (1,1) logical = false
        kwargs.storefilenames logical = false
        kwargs.coordinates (1,:) {mustBeMember(kwargs.coordinates, {'x', 'y', 'z'})} = {'x', 'z'}
        kwargs.components (1,:) {mustBeMember(kwargs.components, {'u', 'v', 'w'})} = {'u', 'w'}
        kwargs.slice (1,:) double = [1, 2] % index to slice imx.Data 
        kwargs.scale (1,1) logical = true % apply scale to velocity
        kwargs.split (1,1) logical = true % split velocity components
        kwargs.regexp (1,1) logical = false
    end

    if isscalar(source)
        if isfolder(source)
            arrdir = dir(fullfile(source, kwargs.pattern));
            kwargs.filenames = arrayfun(@(d) string(fullfile(d.folder,d.name)), arrdir);
            n = numel(unique(arrayfun(@(d) string(d.folder), arrdir)));
            kwargs.filenames = reshape(kwargs.filenames, [], n);
        else
            if kwargs.regexp
                dr = dir(source);
                nf = numel(unique(arrayfun(@(x)string(x.folder),dr)));
                kwargs.filenames = arrayfun(@(x)string(fullfile(x.folder,x.name)),dr);
                kwargs.filenames = reshape(kwargs.filenames,[],nf);
            else
                kwargs.filenames = source;
            end
        end
    else
        kwargs.filenames = source;
    end

    szf = size(kwargs.filenames);
    nf = numel(kwargs.filenames); % number files
    ng = cell(nf, 1); % coordinates grid
    n = cell(nf, 1); % index to reshape data
    scc = cell(nf, 1); % coordinate scale
    scv = cell(nf, 1); % velocity scale
    vel = cell(nf, 1); % velocity data

    % loop load files
    for i = 1:nf
        imx = readimx(char(kwargs.filenames(i)));
        ng{i} = [imx.Nx, imx.Ny];
        scc{i} = {imx.ScaleX, imx.ScaleY};
        scv{i} = imx.ScaleI(1);
        temp = reshape(imx.Data, [ng{i}, size(imx.Data,2)/ng{i}(2)]);
        if ~isempty(kwargs.slice); temp = temp(:,:,kwargs.slice); end
        n{i} = cat(2, num2cell(ng{i}), ones(1, size(temp, 3)));
        vel{i} = temp;
    end

    if numel(unique(cell2mat(ng))) == 2
        m = 1;
    else
        m = nf;
    end

    coord = cell(m ,1);
    parfor (i = 1:m, backgroundPool)
        temp = cellfun(@(x) 1:x, num2cell(ng{i}), 'UniformOutput', false);
        [temp{:}] = ndgrid(temp{:});
        coord{i} = cellfun(@(c,s) c.*s(1)+s(2), temp, scc{i}, 'UniformOutput', false);        
    end
    coord = [coord{:}];
    % coord = cellfun(@(x) coord(:,x), num2cell(1:size(coord,1)), 'UniformOutput', false);

    if kwargs.scale
        vel = cellfun(@(x,c1,c2) x.*shiftdim(sign([c1{1}(1),c1{2}(1)]),-1)*c2, ...
            vel, scc, scv, 'UniformOutput', false);
    end

    vel = cellfun(@(x,n) squeeze(mat2cell(x,n{:})), vel, n, 'UniformOutput', false);
    vel = [vel{:}];
    vel = cellfun(@(x) vel(x,:), num2cell(1:size(vel,1)), 'UniformOutput', false);

    % concatenate and reshape
    if m == 1
        vel = cellfun(@(x) cat(3, x{:}), vel, 'UniformOutput', false);
        vel = cellfun(@(x) reshape(x, [size(x,[1,2]),szf]), vel, 'UniformOutput', false);
    end

    data = cell2struct(cat(2, coord, vel), cat(2, kwargs.coordinates, kwargs.components), 2);

    if kwargs.storefilenames; data.filenames = kwargs.filenames; end
end