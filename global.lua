global = {}

global.activeSub = nil
global.activeTrackId = 0
global.lastTrackId = 0

global.activeEffectScope = nil
global.batchDepth = 0
global.queuedEffects = nil
global.queuedEffectsTail = nil
global.linkPool = nil

function global.nextTrackId()
    global.lastTrackId = global.lastTrackId + 1
    return global.lastTrackId
end

function global.setActiveSub(sub, trackId)
    global.activeSub = sub
    global.activeTrackId = trackId
end

function global.startBatch()
    global.batchDepth = global.batchDepth + 1
end

function global.endBatch()
    global.batchDepth = global.batchDepth - 1
    if global.batchDepth <= 0 then
        global.drainQueuedEffects()
    end
end

function global.drainQueuedEffects()
    while global.queuedEffects do
        local effect = global.queuedEffects
        local queuedNext = effect.nextNotify

        if queuedNext then
            effect.nextNotify = nil
            global.queuedEffects = queuedNext
        else
            global.queuedEffects = nil
            global.queuedEffectsTail = nil
        end

        effect:notify()
    end
end

function global.do_func(func, ...)
	if func then
        return func(...)
    end
end