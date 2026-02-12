function varargout = cellplot(plotname, varargin, popt, pax, pset, pclb, plgd, plin, proi)
    arguments (Input)
        plotname {mustBeMember(plotname, {'plot', 'scatter', 'contour', 'contourf', 'imagesc', 'surf', 'pcolor', 'plot3', 'xregion', 'yregion'})}
    end
    arguments (Input, Repeating)
        varargin {mustBeA(varargin, {'int8', 'int16', 'int32', 'int64', 'single', 'double', 'cell'})}
    end
    arguments (Input)
        popt.parent = []
        popt.axpos (1,:) double = []
        popt.docked (1,1) logical = false
        popt.split (1,1) logical = false
        popt.merge (1,:) {mustBeA(popt.merge, {'double', 'cell'})} = [] % merge axes children to one axis
        popt.probe (1,:) double = []
        popt.addax = []
        popt.customize (1,1) logical = true % enable axes customization
        popt.ans {mustBeMember(popt.ans, {'cell', 'struct'})} = 'cell'
        % axis properties
        pax.axis {mustBeMember(pax.axis, {'tight', 'normal', 'manual', 'padded', 'tickaligned', ...
            'auto', 'auto x', 'auto y', 'auto xy', 'fill', 'equal', 'image', 'square', 'vis3d', ...
            'auto', 'auto z', 'auto xz', 'auto yz'})} = 'auto'
        pax.xscale {mustBeMember(pax.xscale, {'linear', 'log'})} = 'linear'
        pax.yscale {mustBeMember(pax.yscale, {'linear', 'log'})} = 'linear'
        pax.zscale {mustBeMember(pax.zscale, {'linear', 'log'})} = 'linear'
        pax.xlabel (1,:) {mustBeA(pax.xlabel, {'char', 'string', 'cell'})} = ''
        pax.ylabel (1,:) {mustBeA(pax.ylabel, {'char', 'string', 'cell'})} = ''
        pax.zlabel (1,:) {mustBeA(pax.zlabel, {'char', 'string', 'cell'})} = ''
        pax.xlim (1,:) {mustBeA(pax.xlim, {'double', 'char', 'string', 'cell'})} = 'auto'
        pax.ylim (1,:) {mustBeA(pax.ylim, {'double', 'char', 'string', 'cell'})} = 'auto'
        pax.zlim (1,:) {mustBeA(pax.zlim, {'double', 'char', 'string', 'cell'})} = 'auto'
        pax.clim (1,:) {mustBeA(pax.clim, {'double', 'char', 'string', 'cell'})} = 'auto'
        pax.grid {mustBeMember(pax.grid, {'on', 'off'})} = 'on'
        pax.box {mustBeMember(pax.box, {'on', 'off'})} = 'on'
        pax.pbaspect (1,3) double = [1,1,1];
        pax.hold {mustBeMember(pax.hold, {'on', 'off'})} = 'on'
        pax.colormap {mustBeMember(pax.colormap, {'parula','turbo','hsv','hot','cool','spring','summer','autumn',...
            'winter','gray','bone','copper','pink','sky','abyss','jet','lines','colorcube','prism','flag','white'})} = 'turbo'
        pax.xticks (1,:) = 'auto'
        pax.yticks (1,:) = 'auto'
        pax.zticks (1,:) = 'auto'
        pax.xticklabels (1,:) = 'auto'
        pax.yticklabels (1,:) = 'auto'
        pax.zticklabels (1,:) = 'auto'
        pax.xtickangle (1,1) double = 0;
        pax.ytickangle (1,1) double = 0;
        pax.ztickangle (1,1) double = 0;
        pax.fontname = 'default'
        pax.title (1,:) {mustBeA(pax.title, {'char', 'string', 'cell'})} = ''
        pax.subtitle (1,:) {mustBeA(pax.subtitle, {'char', 'string', 'cell'})} = ''
        pax.colororder {mustBeMember(pax.colororder, {'gem', 'gem12', ...
            'glow', 'glow12', 'sail', 'reef', 'meandow', 'dye', 'earth'})} = 'gem'
        pax.linestyleorder {mustBeMember(pax.linestyleorder, {'.', 'o', 's', ...
            '<', '>', '^', 'd', '*', 'mixedstyles', 'mixedmarkers'})} = 'mixedstyles'
        % `set(ax,...)` properties
        pset.layer {mustBeMember(pset.layer, {'bottom', 'top'})} = 'top'
        pset.colorscale {mustBeMember(pset.colorscale, {'linear', 'log'})} = 'linear'
        pset.tag {mustBeA(pset.tag, {'char', 'string', 'cell'})} = ''
        % colobar properties
        pclb.colorbar {mustBeMember(pclb.colorbar, {'on', 'off'})} = 'off'
        pclb.clabel {mustBeA(pclb.clabel, {'char', 'string', 'cell'})} = ''
        pclb.clocation {mustBeMember(pclb.clocation, {'north', 'south', 'east', ...
            'west', 'northoutside', 'southoutside', 'eastoutside', 'westoutside', 'manual', ...
            'layout'})} = 'eastoutside'
        pclb.corientation {mustBeMember(pclb.corientation, {'vertical', 'horizontal'})} = 'vertical'
        pclb.cinterpreter {mustBeMember(pclb.cinterpreter, {'latex', 'tex', 'none'})} = 'tex'
        pclb.cexponent (1,:) {mustBeA(pclb.cexponent, {'double', 'cell'})} = 0
        % legend properties
        plgd.legend {mustBeMember(plgd.legend, {'on', 'off'})} = 'off'
        plgd.ltitle {mustBeA(plgd.ltitle, {'char', 'string', 'cell'})} = ''
        plgd.llocation {mustBeMember(plgd.llocation, {'north','south','east','west', ...
            'northeast','northwest','southeast','southwest','northoutside','southoutside', ...
            'eastoutside','westoutside','northeastoutside','northwestoutside', ...
            'southeastoutside','southwestoutside','best','bestoutside','layout','none'})} = 'best'
        plgd.lorientation {mustBeMember(plgd.lorientation , {'vertical', 'horizontal'})} = 'vertical'
        plgd.linterpreter {mustBeMember(plgd.linterpreter , {'latex', 'tex', 'none'})} = 'tex'
        plgd.lbackgroundalpha {mustBeA(plgd.lbackgroundalpha, {'double', 'cell'})} = 1
        plgd.lnumcolumns {mustBeA(plgd.lnumcolumns, {'double', 'cell'})} = 1
        plgd.ltextcolor {mustBeA(plgd.ltextcolor, {'double', 'char', 'string', 'cell'})} = []
        plgd.ledgecolor {mustBeA(plgd.ledgecolor, {'double', 'char', 'string', 'cell'})} = []
        plgd.lstring {mustBeA(plgd.lstring, {'double', 'char', 'string', 'cell'})} = []
        % line properties
        plin.cyclingmethod {mustBeMember(plin.cyclingmethod, {'withcolor', 'beforecolor', 'aftercolor'})} = 'withcolor'
        plin.linestyle {mustBeMember(plin.linestyle, {'-', '--', ':', '-.', 'none'})} = '-'
        plin.levels {mustBeA(plin.levels, {'double', 'cell'})} = []
        plin.labelcolor {mustBeA(plin.labelcolor, {'double', 'char', 'string', 'cell'})} = []
        plin.facecolor {mustBeMember(plin.facecolor, {'flat', 'interp', 'none', 'red', 'blue', 'white', 'black'})} = 'flat'
        plin.facealpha (1,:) double = 1
        plin.edgecolor {mustBeMember(plin.edgecolor , {'flat', 'interp', 'none', 'red', 'blue', 'white', 'black'})} = 'flat'
        plin.edgealpha (1,:) double = 1
        plin.view {mustBeA(plin.view, {'double', 'cell'})} = [0, 90]
        plin.displayname {mustBeA(plin.displayname, {'char', 'string', 'cell'})} = ''
        plin.ltag {mustBeA(plin.ltag, {'char', 'string', 'cell'})} = ''
        plin.linealpha (1,1) double = 1
        % roi properties
        proi.draw {mustBeMember(proi.draw, {'none', 'drawpoint', 'drawline', ...
            'drawrectangle', 'drawpolygon', 'drawpolyline', 'drawxline', ...
            'drawyline', 'drawxrange', 'drawyrange'})} = 'none'
        proi.rtarget (1,:) {mustBeA(proi.rtarget, {'double', 'cell'})} = []
        proi.rnumber (1,:) {mustBeA(proi.rnumber, {'double', 'cell'})} = []
        proi.rposition {mustBeA(proi.rposition, {'double', 'cell'})} = []
        proi.rlabel {mustBeA(proi.rlabel, {'char', 'string', 'cell'})} = ''
        proi.rinteraction {mustBeMember(proi.rinteraction , {'all', 'none', 'translate'})} = 'all' % region selection behaviour
        proi.rstripecolor = 'none'
        proi.ralpha (1,1) double = 1
        proi.rtag {mustBeA(proi.rtag, {'char', 'string', 'cell'})} = ''
        proi.rmarkersize = []
        proi.rlinewidth = []
        proi.rvisible {mustBeMember(proi.rvisible, {'on', 'off'})} = 'on'
        proi.rcolororder {mustBeMember(proi.rcolororder, {'on', 'off'})} = 'on'
        proi.rlinealign {mustBeMember(proi.rlinealign, {'on', 'off'})} = 'off'
        proi.rnumlabel {mustBeMember(proi.rnumlabel, {'on', 'off'})} = 'off'
        proi.rlabelalpha (1,1) double = 1
        proi.rsnap {mustBeMember(proi.rsnap, {'on', 'off'})} = 'on'
        proi.redgealpha (1,:) {mustBeA(proi.redgealpha, {'double', 'cell'})} = 1
        proi.rfacealpha (1,:) {mustBeA(proi.rfacealpha, {'double', 'cell'})} = 1
        proi.rweight (1,:) double = [] 
    end

    arguments (Output, Repeating)
        varargout
    end

    %% plot

    if ~isa(plotname, 'cell'); plotname = {plotname}; end
    if isscalar(plotname) & isa(varargin{1}, 'cell'); plotname = repmat(plotname, 1, numel(varargin{1})); end
    plt = struct(plot = 1, scatter = 1, contour = 2, contourf = 2, imagesc = 2, ...
        surf = 2, pcolor = 2, plot3 = 2, xregion = 1, yregion = 1);
    dims = cellfun(@(p) plt.(p), plotname);
    % define custom function
    funcs = cell2struct(cellfun(@(f) str2func(f), fieldnames(plt), 'UniformOutput', false), fieldnames(plt));
    funcs.xregion = @(varargin) plotregion('x',varargin{:});
    funcs.yregion = @(varargin) plotregion('y',varargin{:});
    funcs.imagesc = @(varargin) imagesc(varargin{1},[min(varargin{2}(:)),max(varargin{2}(:))],...
        [min(varargin{3}(:)),max(varargin{3}(:))],varargin{4});
    pltfunc = cellfun(@(p) funcs.(p), plotname, 'UniformOutput', false);

    % parse data
    if ~isempty(popt.probe)
        probe = cell(1, numel(varargin));
        for i = 1:numel(probe)
            for j = popt.probe
                probe{i} = cat(2, probe{i}, varargin{i}{j});
                varargin{i}{j} = [];
            end
        end
    end
    varargin = cellfun(@(v) terop(isvector(v),v(:),v), varargin, UniformOutput = false);
    [data, dg] = wraparrbycell(varargin{:}, dims = dims);
    dgn = splitapply(@numel, dg, dg);

    % create data-axis map 
    ag = zeros(1, numel(data));
    if isempty(popt.axpos); popt.axpos = zeros(1, numel(dgn)); end
    for i = 1:numel(popt.axpos)
        ind = i == dg;
        if isnan(popt.axpos(i))
            ag(ind) = (1:dgn(i)) + max(ag);
        else
            if popt.axpos(i) == 0
                ag(ind) = 1 + max(ag);
            else
                ag(ind) = popt.axpos(i);
            end
        end
    end

    [dg; ag];

    % create axes
    switch class(popt.parent)
        case 'matlab.graphics.layout.TiledChartLayout'
            tl = popt.parent;
            axs = cellfun(@(~) nexttile(tl), num2cell(1:max(ag(:))), UniformOutput = false);
            fig = tl.Parent;
        case 'cell'
            if prod(cellfun(@(a) isa(a, 'matlab.graphics.axis.Axes'), popt.parent)) == 1
                axs = popt.parent;
                fig = axs{1}.Parent.Parent;
            end
        case 'double'
            if isempty(popt.parent)
                if popt.docked; fig = figure(WindowStyle = 'docked'); else; clf; fig = gcf; end
                tl = tiledlayout(fig, 'flow');
                axs = cellfun(@(~) nexttile(tl), num2cell(1:max(ag(:))), UniformOutput = false);
            end
    end

    % plot
    cellfun(@(a) hold(a,'on'), axs, UniformOutput = false)
    cellfun(@(a,d,g) pltfunc{g}(axs{a}, d{:}), ...
        num2cell(ag), data, num2cell(dg), UniformOutput = false);
 
    % gather axes children
    plts = flip(setdiff(findobj(findobj(fig,'Type','Axes'),'-depth',1), ...
        findobj(findobj(fig,'Type','Axes'),'-depth',0),'stable'));

    if ~isempty(popt.addax); axs = cat(2, axs, cellfun(@(~) nexttile(tl), num2cell(1:popt.addax), UniformOutput = false)); end

    %% customize
    if popt.customize

        cellfun(@(ax) {colorbar(ax), legend(ax)}, ...
            axs, UniformOutput = false);

        % customize axes appearance
        % define specific name functions (`xlabel(ax, ...)` et al.)
        fax = cellfun(@(s) str2func(s), fieldnames(pax), UniformOutput = false);
        % define `set(ax, ...)` functions
        fset = cellfun(@(param) @(ax, val) set(ax, param, val), fieldnames(pset), UniformOutput = false);
        % collect functions
        fax = cell2struct(cat(1, fax, fset), cat(1, fieldnames(pax), fieldnames(pset)));
        % merge structures
        pax = cat(2, namedargs2cell(pax), namedargs2cell(pset));
        pax = cell2struct(pax(2:2:end), pax(1:2:end), 2);
        cellapply(axs, fax, pax);
    
        % customize colorbars appearance
        fclb = pclb;
        fclb.colorbar = @(obj, value) set(obj, 'Visible', value);
        fclb.clabel = @(obj, value) set(obj.Label, 'String', value);
        fclb.clocation = @(obj, value) set(obj, 'Location', value);
        fclb.corientation = @(obj, value) set(obj, 'Orientation', value);
        fclb.cinterpreter = @(obj, value) set(obj.Label, 'Interpreter', value);
        fclb.cexponent = @(obj, value) set(obj.Ruler, 'Exponent', value, 'TickLabelFormat', '%0.1f');
        cellapply(num2cell(flip(findobj(fig, 'Type', 'ColorBar'))), fclb, pclb);
    
        % customize legends appearance
        flgd = plgd;
        flgd.legend = @(obj, value) set(obj, 'Visible', value);
        flgd.ltitle = @(obj, value) [set(obj.Title, 'String', value), set(obj.Title, 'FontWeight', 'Normal')];
        flgd.llocation = @(obj, value) set(obj, 'Location', value);
        flgd.lorientation = @(obj, value) set(obj, 'Orientation', value);
        flgd.linterpreter = @(obj, value) set(obj, 'Interpreter', value);
        flgd.lbackgroundalpha = @(obj, value) set(obj, 'BackgroundAlpha', value);
        flgd.lnumcolumns = @(obj, value) set(obj, 'NumColumns', value);
        flgd.ltextcolor = @(obj, value) teropf(isempty(value), @() [], @() set(obj, 'TextColor', value));
        flgd.ledgecolor = @(obj, value) teropf(isempty(value), @() [], @() set(obj, 'EdgeColor', value));
        flgd.lstring = @(obj, value) teropf(isempty(value), @() [], @() set(obj, 'String', value));
        cellapply(num2cell(flip(findobj(fig, 'Type', 'Legend'))), flgd, plgd);
    end

    % customize line
    % fexpr = @(obj, param, value) teropf(isempty(value)|isprop(obj,param), @() [], @() set(findobj(obj.Children, '-property', param), param, value));
    fexpr = @(obj, param, value) teropf(isempty(value)|isprop(obj,param), @() [], @() set(findobj(obj.Children, '-property', param), param, value));
    temp = @(obj, param, value) cellfun(@(c,d) set(c, param, d), num2cell(flip(findobj(obj.Children, '-property', param))), ...
        terop(isa(value,'cell'), value(:), {value}), UniformOutput = false);
    fcond2 = @(obj, param, value) teropf(isempty(value), @() [], @() temp(obj, param, value));
    flin = plin;
    flin.cyclingmethod = @(obj, value) set(obj, 'LineStyleCyclingMethod', value);
    flin.linestyle = @(obj, value) fexpr(obj, 'LineStyle', value);
    flin.levels = @(obj, value) fexpr(obj, 'LevelList', value);
    flin.labelcolor = @(obj, value) fexpr(obj, 'LabelColor', value);
    flin.view = @(obj, value) set(obj, 'View', value);
    flin.displayname = @(obj, value) fcond2(obj, 'Displayname', value);
    flin.facecolor = @(obj, value) fexpr(obj, 'FaceColor', value);
    flin.facealpha = @(obj, value) fexpr(obj, 'FaceAlpha', value);
    flin.edgecolor = @(obj, value) fexpr(obj, 'EdgeColor', value);
    flin.edgealpha = @(obj, value) fexpr(obj, 'EdgeAlpha', value);
    flin.ltag = @(obj, value) set(findobj(obj.Children,'Tag',''), 'Tag', value);
    flin.linealpha = @(obj, value) teropf(isprop(obj,'Color'), @() set(obj, 'Color', [obj.Color, value], @() []));
    cellapply(axs, flin, plin);

    %% roi
    if ~strcmp(proi.draw, "none")

        if ~isa(proi.draw, 'cell'); proi.draw = {proi.draw}; end

        ndraw = numel(proi.draw);

        if isempty(proi.rposition); proi.rposition = repelem({{[]}}, ndraw); end 
        if ~isa(proi.rposition, 'cell'); proi.rposition = {{proi.rposition}}; end
        proi.rposition = cellfun(@(p) terop(isa(p,'cell'),p,{p}), proi.rposition, UniformOutput = false);

        if isempty(proi.rtarget);  proi.rtarget = ones(1, ndraw); end
        if ~isa(proi.rtarget, 'cell'); proi.rtarget = num2cell(proi.rtarget); end
        proi.rtarget = cellfun(@(x) terop(isempty(x), 1, x), proi.rtarget, 'UniformOutput', false);
        if isscalar(proi.rtarget); proi.rtarget = repelem(proi.rtarget, ndraw); end

        if isempty(proi.rnumber); proi.rnumber = cellfun(@(p) numel(p), proi.rposition); end
        if ~isa(proi.rnumber, 'cell'); proi.rnumber = num2cell(proi.rnumber); end
        proi.rnumber = cellfun(@(x) terop(isempty(x), 1, x), proi.rnumber, 'UniformOutput', false);
        if isscalar(proi.rnumber); proi.rnumber = repelem(proi.rnumber, ndraw); end

        if ~isa(proi.rsnap, 'cell'); proi.rsnap = repelem({proi.rsnap}, ndraw); end

        % draw roi
        funcs = cellfun(@(draw) str2func(draw), proi.draw, UniformOutput = false);
        expr = @(f,t,g,p) teropf(isempty(p{1}), @() f(plts(t).Parent, 'UserData', struct(target = plts(t), group = g)), ...
            @() f(plts(t).Parent, 'Position', p{1}, 'UserData', struct(target = plts(t), group = g, tindex = t)));
        rois = cellfun(@(f,t,g,p) expr(f,t,g,p), ...
            funcs, proi.rtarget, num2cell(1:numel(funcs)), proi.rposition, UniformOutput = false);
        
        rnumber = proi.rnumber;
        rposition = cellfun(@(p,n) terop(isscalar(p), repelem(p,n), p), proi.rposition, proi.rnumber, 'UniformOutput', false);
        rsnap = proi.rsnap;
        rweight = proi.rweight;

        proi = rmfield(proi, 'draw');
        proi = rmfield(proi, 'rtarget');
        proi = rmfield(proi, 'rnumber');
        proi = rmfield(proi, 'rposition');
        proi = rmfield(proi, 'rsnap');
        proi = rmfield(proi, 'rweight');

        froi = proi;
        froi.rlabel = @(obj, value) set(obj, 'Label', value);
        froi.rinteraction = @(obj, value) set(obj, 'Interaction', value);
        froi.rstripecolor  = @(obj, value) set(findobj(obj,'-property','StripeColor'), 'StripeColor', value);
        froi.ralpha = @(obj, value) set(findobj(obj,'-property','Alpha'), 'Alpha', value);
        froi.rtag = @(obj, value) set(obj, 'Tag', value);
        froi.rmarkersize = @(obj, value) teropf(isempty(value), @() [], @() set(obj, 'MarkerSize', value));
        froi.rlinewidth = @(obj, value) teropf(isempty(value), @() [], @() set(obj, 'LineWidth', value));
        froi.rvisible = @(obj, value) set(obj, 'Visible', value);
        froi.rcolororder = @(obj, value) set(obj, 'UserData', setfield(obj.UserData, 'colororder', value));
        froi.rlinealign = @(obj, value) set(obj, 'UserData', setfield(obj.UserData, 'linealign', value));
        froi.rnumlabel = @(obj, value) set(obj, 'UserData', setfield(obj.UserData, 'numlabel', value));
        froi.rlabelalpha = @(obj, value) set(obj, 'LabelAlpha', value);
        froi.redgealpha = @(obj, value) teropf(isprop(obj,'EdgeAlpha'), @() set(obj, 'EdgeAlpha', value), @() []);
        froi.rfacealpha = @(obj, value) teropf(isprop(obj,'FaceAlpha'), @() set(obj, 'FaceAlpha', value), @() []);
        cellapply(rois, froi, proi);

        % set snap property
        cellfun(@(r,s) set(r, 'UserData', setfield(r.UserData, 'snap', s)), rois, rsnap);
        % replicate roi object
        cellfun(@(r,n) cellfun(@(n) copyobj(r, r.Parent), num2cell(1:n-1)), rois, rnumber, ...
            UniformOutput = false);
        % get roi object list
        rois = flip(findobj(fig, 'Type','images.roi'));
        % define group mask
        rgroup = arrayfun(@(r) r.UserData.group, rois);
        % set position
        expr = @(r,i) teropf(isempty(rposition{r.UserData.group}{i}), @() nan, ...
            @() set(r, 'Position', rposition{r.UserData.group}{i}));
        splitapply(@(roi) {arrayfun(@(r,i) {expr(r,i)}, roi, (1:numel(roi))')}, rois, rgroup);
        % set snap hander
        cellfun(@(r) teropf(strcmp(r.UserData.snap, 'on'), @() addlistener(r, 'MovingROI', @(s,e) roisnaphandler(s, r.UserData.target)), @() []), ...
            num2cell(rois), 'UniformOutput', false);
        % set colors
        colors = repmat(colororder, max([max(cell2mat(rnumber)), numel(funcs)]), 1);
        expr = @(r,i) terop(strcmp(r.UserData.colororder,'on'), colors(i,:), colors(r.UserData.group,:));
        splitapply(@(roi) arrayfun(@(r,i) set(r, 'Color', expr(r,i)), roi, (1:numel(roi))'), rois, rgroup);
        % set numbered label
        expr = @(r,i) terop(strcmp(r.UserData.numlabel,'on'), num2str(i), r.Label);
        splitapply(@(roi) arrayfun(@(r,i) set(r, 'Label', expr(r,i)), roi, (1:numel(roi))'), rois, rgroup);
        % set aligment event
        expr = @(r,roi) teropf(strcmp(r.UserData.linealign,'on'), ...
            @() addlistener(r, 'MovingROI', @(s,e) roievtlinalig(e,num2cell(roi), rweight)), ...
            @() nan);
        splitapply(@(roi) {arrayfun(@(r) {expr(r,roi)}, roi)}, rois, rgroup);
    else
        rois = [];
    end

    %% merge axis
    if ~isempty(popt.merge)
        if isa(popt.merge, 'double'); popt.merge = {popt.merge}; end
        for i = 1:numel(popt.merge)
            [m, j] = min(popt.merge{i});
            popt.merge{i}(j) = [];
            cellfun(@(a) copyobj(a.Children, axs{m}), axs(popt.merge{i}))
            cellfun(@(a) delete(a), axs(popt.merge{i}));
            axs{popt.merge{i}} = axs{m};
        end
    end

    %% convert tiles to standalone figures
    if popt.split
        hax = flip(findobj(fig, 'type', 'axes'));
        hclb = flip(findobj(fig, 'type', 'colorbar'));
        figs = {};
        for i = 1:length(hax)
            if popt.docked; figs{i} = figure(WindowStyle = 'docked'); else; figs{i} = figure; end
            if i <= numel(hclb)
                obj = [hclb(i), hax(i), hax(i).Legend];
            else
                obj = [hax(i), hax(i).Legend];
            end
            copyobj(obj, figs{i})
            set(findobj(figs{i},'Type','Axes'), Units = 'normalized', Position = [0.1 0.2 0.7 0.6])
        end
        delete(fig)
        % attach children/parent dependency for ROI objects
        axs = cellfun(@(f)findobj(f, 'Type', 'Axes'), figs, UniformOutput = false)';
        rois = flip(findobj(cell2mat(axs), 'Type','images.roi'));
        % gather axes children
        plts = flip(cell2mat(cellfun(@(a) a.Children, axs, UniformOutput = false)));
        % set target objects
        cellfun(@(r) set(r, 'UserData', setfield(r.UserData,'target',plts(r.UserData.tindex))), num2cell(rois))
        % set snap hander
        cellfun(@(r) addlistener(r, 'MovingROI', @(s,e) roisnaphandler(s, r.UserData.target)), ...
            num2cell(rois));
        % set aligment event
        expr = @(r,roi) teropf(strcmp(r.UserData.linealign,'on'), ...
            @() addlistener(r, 'MovingROI', @(s,e) roievtlinalig(e,num2cell(roi), rweight)), ...
            @() nan);
        splitapply(@(roi) {arrayfun(@(r) expr(r,roi), roi)}, rois, rgroup);
    end

    switch popt.ans
        case 'cell'
            varargout = cell(1,4);
            [varargout{:}] = deal(plts,axs,rois,@resfunc);
        case 'struct'
            varargout{1} = struct(plts = plts, axs = axs, rois = rois, resfunc = @resfunc);
    end

    function res = resfunc()
        res = struct;
        if ~isempty(rois)
            res.rposition = arrayfun(@(r) r.Position, rois, 'UniformOutput', false);
            res.rgroup = rgroup;
            res.rgpos = splitapply(@(r) {r}, res.rposition, res.rgroup);
        end
    end

end

function [funcs, params] = cellapply(objs, hdls, params)
    [funcs, params] = parseargs(numel(objs), params);
    funcs = cellfun(@(func) cellfun(@(f) hdls.(f), func, ...
        UniformOutput = false), funcs, UniformOutput = false);
    cellfun(@(obj,func,param) cellfun(@(f,p) f(obj,p{:}), func(:), param(:), UniformOutput = false), ...
        objs(:), funcs(:), params(:), UniformOutput = false);
end

function roievtlinalig(evt, rois, weight)
    % event to align ROI object by line
    if isempty(weight)
        p = numel(rois);
    else
        p = rescale(weight);
        linspace = @(x1, x2, w) x1 + (x2-x1)*w;
    end
    
    if isa(evt.Source, 'images.roi.Rectangle')
        cellfun(@(r) set(r, 'Position', [r.Position(1:2), evt.CurrentPosition(:,3:4)]), rois);
    end
    pos = cellfun(@(r) r.Position, rois, UniformOutput = false);
   
    pos = cell2mat(arrayfun(@(p1,p2)shiftdim(linspace(p1,p2,p),-1),pos{1},pos{end},'UniformOutput',false));
    pos = mat2cell(pos,size(pos,1),size(pos,2),ones(1,size(pos,3)));
    cellfun(@(r, p) set(r, 'Position', p), rois, pos(:));
    cellfun(@(r)  teropf(strcmp(r.UserData.snap, 'on'), @() roisnaphandler(r, r.UserData.target), @() []), ...
        rois, 'UniformOutput', false);
end


function plotregion(type,ax,varargin)
    arguments (Input)
        type {mustBeMember(type, {'x', 'y'})}
        ax
    end
    arguments  (Input, Repeating)  
        varargin
    end
    switch type
        case 'x'
            ind = [1, 2];
        case 'y'
            ind = [2, 1];
    end
    if isscalar(varargin)
        bin = varargin{1};
        pos = 1:numel(bin);
    else
        pos = varargin{ind(1)};
        bin = varargin{ind(2)};
    end
    bin = parseregion(bin);
    args = {ax,pos(bin(:,1)),pos(bin(:,2))};
    switch type
        case 'x'
            xregion(args{:})
        case 'y'
            yregion(args{:})
    end
end