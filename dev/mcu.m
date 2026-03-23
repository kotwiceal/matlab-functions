classdef mcu < handle
properties (Access = public)
    address {mustBeText} = "10.10.1.1"
    port {mustBeInteger} = 8090
    url struct
    dq struct % data queue
    figures struct
end
properties (Access = private)
    dql (:,1) cell = {'log';'getview'} % data queue label
    figl (:,1) cell = {'mcu'} % figure labels
end
methods (Access = public)
    function obj = mcu(address,port,url,params)
        arguments
            address {mustBeText} = "10.10.1.1"
            port {mustBeInteger} = 8090
            url struct = struct(get="get-param",set="set-param")
            params.dqlog parallel.pool.DataQueue
        end
        obj.address = address; obj.port = port;
        obj.url = structfun(@(x)sprintf("http://%s:%d/%s",obj.address,obj.port,x),url,'UniformOutput',false);
        % define data queues
        obj.dq = cell2struct(cellfun(@(x)parallel.pool.DataQueue,obj.dql,'UniformOutput',false),obj.dql);
        if isfield(params,'dqlog')
            obj.dq.log = params.dqlog;
        else
            if isempty(getCurrentWorker)
                afterEach(obj.dq.log,@disp)
            end
        end
        if isempty(getCurrentWorker)
            afterEach(obj.dq.getview,@obj.getview)
        end
        % define figures
        obj.figures = cell2struct(cellfun(@(x)figure('Name',x,'WindowStyle','docked','NumberTitle','off','Visible','off'),...
            obj.figl,'UniformOutput',false),obj.figl);
    end
    function [data, state] = get(obj,params)
        arguments (Input)
            obj
            params.dashboard (1,1) logical = true
            params.dquser (1,:) parallel.pool.DataQueue = parallel.pool.DataQueue
        end
        arguments (Output)
            data (1,:) struct
            state (1,1) logical
        end
        [data, state] = mcu.http_get(obj.url.get,obj.dq.log,'dquser',[obj.dq.getview,params.dquser]);
    end
    function state = set(obj,data,params)
        arguments (Input)
            obj
            data (1,1) struct
            params.dquser (1,:) parallel.pool.DataQueue = parallel.pool.DataQueue
        end
        arguments (Output)
            state (1,1) logical
        end
        state = mcu.http_post(obj.url.set,data,obj.dq.log,'dquser',params.dquser);
    end
    function delete(obj)
        structfun(@(x)delete(x),obj.dq);
    end
    function getview(obj,data)
        arguments
            obj
            data (1,:) struct
        end
        amplitude = data.dac.value;
        offset = data.dac_offset.value;

        flabel = 'mcu';
        f = obj.figures.(flabel);
        if ~isvalid(f)
            f = figure('Name',flabel,'WindowStyle','docked','NumberTitle','off');
            obj.figures.(flabel) = f; 
        end
        set(f,'Visible','on'); t = f.Children;
        if isempty(t)
            t = tiledlayout(f);
            if isempty(t.Children)
                arrayfun(@(x)set(nexttile(t),'Box','on','XGrid','on','YGrid','on'),1:2)
                arrayfun(@(x)hold(x,'on'),t.Children)
            end
        end
        axs = flip(findobj(t,'type','Axes'));
        arrayfun(@(x)cla(x),axs);

        ax = axs(1);
        bar(ax,amplitude); xlabel(ax,'channel'); ylabel(ax,'amplitude');
        ax = axs(2);
        bar(ax,offset); xlabel(ax,'channel'); ylabel(ax,'offset');
        sgtitle(f,string(datetime))
    end
end
methods (Static)
    function [data, state] = http_get(url,dqlog,params)
        arguments (Input)
            url {mustBeText}
            dqlog (1,1) parallel.pool.DataQueue
            params.dquser (1,:) parallel.pool.DataQueue
        end
        arguments (Output)
            data (1,:) struct
            state (1,1) logical
        end
        data = struct([]); state = false;
        d = dbstack; flabel = sprintf("@%s:",d(1).name);
        try
            request = matlab.net.http.RequestMessage;
            response = request.send(url);
            data = response.Body.Data;
            state = true;
            if isfield(params,'dquser'); arrayfun(@(dq)send(dq,data),params.dquser); end
            send(dqlog,sprintf("%s HTTP GET request: %s",flabel,jsonencode(data)));
        catch ex
            send(dqlog,sprintf("%s HTTP GET request failed: %s",flabel,ex.message));
        end
    end
    function state = http_post(url,data,dqlog,params)
        arguments (Input)
            url {mustBeText} 
            data (1,1) struct
            dqlog (1,1) parallel.pool.DataQueue
            params.dquser (1,:) parallel.pool.DataQueue
        end
        arguments (Output)
            state (1,1) logical
        end
        d = dbstack; flabel = sprintf("@%s:",d(1).name);
        state = false;
        try
            data = jsonencode(data);
            request = matlab.net.http.RequestMessage('POST', ...
                [matlab.net.http.field.ContentTypeField('application/json'), ...
                matlab.net.http.field.AcceptField('application/json')], data);
            request.send(url);
            if isfield(params,'dquser'); arrayfun(@(dq)send(dq,data),params.dquser); end
            state = true;
            send(dqlog, sprintf("%s HTTP POST request: %s",flabel,data));
        catch ex
            send(dqlog,sprintf("%s HTTP POST request failed: %s",flabel,ex.message));
        end
    end
end
end