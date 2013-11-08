function liveParts(mdl, start, duration, freq)

%% Form channel list
load_system(mdl);
liveParts = find_system(mdl, 'FollowLinks', 'on', 'LookUnderMasks', 'all', 'RegExp', 'on', 'Tag', '(LiveConstant|LiveMatrix|LiveFilter)');
disp([num2str(numel(liveParts)) ' LiveParts found']);

chans = cell(size(liveParts));

for n = 1:numel(liveParts)
    chans{n} = liveChans(liveParts{n});
    disp(['    ' liveParts{n} ' :: ' num2str(numel(chans{n}(:))) ' channels']);
end

%% Get data and store it in a containers.Map

chanList = {};
for n = 1:numel(chans)
    chanList = [chanList chans{n}(:)']; %#ok<AGROW>
end
chanList = sort(unique(chanList));
disp(['Requesting ' num2str(duration) ' seconds of data for ' num2str(numel(chanList)) ...
    ' channels, starting at GPS time ' num2str(start)]);
data = cacheGetData(chanList, 'raw', start, duration);

dataByChan = containers.Map();
for n = 1:numel(data)
    if any(diff(data(n).data) ~= 0)
        warning([data(n).name ' is not constant during the segment']);
    end
    dataByChan(data(n).name) = mean(data(n).data);
end

%% Apply params

for n = 1:numel(liveParts)
    liveParams(liveParts{n}, chans{n}, dataByChan, start, duration, freq);
end

end

function chans = liveChans(blk)

blkType = get_param(blk, 'Tag');
blkVars = get_param(blk, 'MaskWSVariables');

switch blkType
    case 'LiveConstant'
        chans = {blkVars(strcmp({blkVars.Name}, 'chan')).Value};
        
    case 'LiveMatrix'
        prefix = blkVars(strcmp({blkVars.Name}, 'prefix')).Value;
        firstRow = blkVars(strcmp({blkVars.Name}, 'firstRow')).Value;
        firstCol = blkVars(strcmp({blkVars.Name}, 'firstCol')).Value;
        lastRow = blkVars(strcmp({blkVars.Name}, 'lastRow')).Value;
        lastCol = blkVars(strcmp({blkVars.Name}, 'lastCol')).Value;
        
        rows = firstRow:lastRow;
        cols = firstCol:lastCol;
        chans = cell(numel(rows), numel(cols));
        for row = 1:numel(rows)
            for col = 1:numel(cols)
                chans{row, col} = [prefix '_' num2str(rows(row)) '_' num2str(cols(col))];
            end
        end

    case 'LiveFilter'
        prefix = blkVars(strcmp({blkVars.Name}, 'prefix')).Value;
        % note: the liveParams function below depends on the ordering of these suffixes
        fmChanSuffixes = {'_SWSTAT', '_OFFSET', '_GAIN', '_LIMIT'};
        chans = cell(size(fmChanSuffixes));
        for n = 1:numel(fmChanSuffixes)
            chans{n} = [prefix fmChanSuffixes{n}];
        end
        
end
        
end

function liveParams(blk, chans, dataByChan, start, duration, freq)

blkType = get_param(blk, 'Tag');
blkVars = get_param(blk, 'MaskWSVariables');

switch blkType
    case 'LiveConstant'
        K = dataByChan(chans{1});
        kVar = get_param(blk, 'K');
        setInBase(kVar, K);

    case 'LiveMatrix'
        [rows, cols] = size(chans);
        M = zeros(rows, cols);
        
        for row = 1:rows
            for col = 1:cols
                M(row, col) = dataByChan(chans{row, col});
            end
        end
        mVar = get_param(blk, 'M');
        setInBase(mVar, M);

    case 'LiveFilter'
        site = blkVars(strcmp({blkVars.Name}, 'site')).Value;
        model = blkVars(strcmp({blkVars.Name}, 'feModel')).Value;
        fmName = blkVars(strcmp({blkVars.Name}, 'fmName')).Value;
        flexTf = blkVars(strcmp({blkVars.Name}, 'flexTf')).Value;
        par.swstat = dataByChan(chans{1});
        par.offset = dataByChan(chans{2});
        par.gain = dataByChan(chans{3});
        par.limit = dataByChan(chans{4});
        ff = find_FilterFile(site, model(1:2), model, start);
        ff2 = find_FilterFile(site, model(1:2), model, start + duration);
        if ~strcmp(ff, ff2)
            warning([model '.txt is not constant during the segment']);
        end
        filters = readFilterFile(ff);
        fm = filters.(fmName);
        for n = 1:10
            [z, p, k] = sos2zp(fm(n).soscoef);
            par.(['fm' num2str(n)]) = d2c(zpk(z, p, k, 1/fm(n).fs), 'tustin');
            if flexTf
                par.(['fm' num2str(n) 'frd']) = frd(par.(['fm' num2str(n)]), freq, 'Units', 'Hz');
            end
        end
        parVar = get_param(blk, 'par');
        setInBase(parVar, par);
        
end
        
end

function setInBase(var, val)
% This function is a kludge to allow things like setting fields of
% structures (not possible with assignin alone)

assignin('base', 'zzz_assignin_kludge_tmp', val);
evalin('base', [var ' = zzz_assignin_kludge_tmp; clear zzz_assignin_kludge_tmp']);

end

function data = cacheGetData(chanList, chanType, start, duration)

global livePartsGetDataCache;

if isempty(livePartsGetDataCache)
    livePartsGetDataCache = {};
end

for n = 1:size(livePartsGetDataCache, 1)
    cachedArgin = livePartsGetDataCache{n, 1};
    cachedArgout = livePartsGetDataCache{n, 2};
    if ~all(cellfun(@(x, y) strcmp(x, y), chanList, cachedArgin{1}))
        continue;
    elseif ~strcmp(chanType, cachedArgin{2})
        continue;
    elseif start ~= cachedArgin{3}
        continue;
    elseif duration ~= cachedArgin{4}
        continue;
    end
    disp('Reusing get_data results from a previous run (cached in the global variable ''livePartsGetDataCache'')');
    data = cachedArgout;
    return;
end

data = get_data(chanList, chanType, start, duration);

livePartsGetDataCache{end+1, 1} = {chanList, chanType, start, duration};
livePartsGetDataCache{end, 2} = data;
livePartsGetDataCache = livePartsGetDataCache(max(end-2, 1):end, :);

end 