function roisnaphandler(roi, target, options)
    arguments
        roi
        target
        options.snap (1,1) logical = true
    end

    chs = flip(roi.Parent.Children);

    if isa(target, 'double')
        try
            target = chs(target);
        catch
            return;
        end
    end

    if ~ismember(target, chs); return; end

    memf = memoize(@procpoint);
    [pos, sz] = memf(target);

    switch class(roi)
        case 'images.roi.Rectangle'
            rpos = roi.Position;
            vrt = [rpos(1), rpos(2); rpos(1)+rpos(3), rpos(2); ...
                rpos(1)+rpos(3), rpos(2)+rpos(4); rpos(1), rpos(2)+rpos(4)];
        otherwise
            vrt = roi.Position;
    end

    k = dsearchn(pos, vrt);
    roi.UserData.linind = k;
    switch class(roi)
        case 'images.roi.Point'
            roi.UserData.linindr = roi.UserData.linind;
        case 'images.roi.Line'
            roi.UserData.linindr = roi.UserData.linind;
        case 'images.roi.Polyline'
            roi.UserData.linindr = roi.UserData.linind;
        otherwise
            [in, on] = inpolygon(pos(:,1), pos(:,2), vrt(:,1), vrt(:,2));
            ind = in | on;
            roi.UserData.linindr = find(ind);        
    end
    vrt = pos(k,:);

    if options.snap
        switch class(roi)
            case 'images.roi.Rectangle'
                vrt = sort(vrt, 1);
                roi.Position = [vrt(1,1), vrt(1,2), ...
                    vrt(4,1)-vrt(1,1), vrt(4,2)-vrt(1,2)];
            otherwise
                roi.Position = vrt;
        end
    end

    roi.UserData.subind = cell(numel(sz), 1);
    [roi.UserData.subind{:}] = ind2sub(sz, roi.UserData.linind);
end

function [p, sz] = procpoint(chobj)
    switch class(chobj)
        case 'matlab.graphics.primitive.Image'
            sz = size(chobj.CData);
            p = cell(1, numel(sz));
            szt = cellfun(@(x) 1:x, num2cell(sz), UniformOutput = false);
            [p{:}] = ndgrid(szt{:});
            p = cell2mat(cellfun(@(x) x(:), p, UniformOutput = false));
        otherwise
            sz = size(chobj.XData);
            p = [chobj.XData(:), chobj.YData(:)];
    end
end