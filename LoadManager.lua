local function safeassert(prefix, cond, msg)
	if not cond then geterrorhandler()(prefix..msg) end
	return cond
end

local function getTOCstring(index, field)
	local str = GetAddOnMetadata(index, field)
	if str then
		local i = 2
		local nextstr = GetAddOnMetadata(index, field..i)
		while nextstr do
			str = str.." "..nextstr
			nextstr = GetAddOnMetadata(index, field..i)
			i = i + 1
		end
		return str
	end
	return ""
end

local function getTOCfunc(addon, meta)
	local str = getTOCstring(addon, meta)
	return str ~= "" and safeassert("Invalid function in "..meta.." for "..(GetAddOnInfo(addon))..": ", loadstring(str))
end

local loadhooks, afterfuncs = {}, {}
local function load(addon, ...)
	local ret = safeassert("Unable to load "..(GetAddOnInfo(addon))..", reason: ", LoadAddOn(addon))
	if ret then
		afterfuncs[addon](...)
		afterfuncs[addon] = nil
	end
end

local dummy = function() return true end
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LOGIN" then --have to scan addons here, because IsAddOnLoadOnDemand() lies before this point (unless it's a reload)
		for addon = 1, GetNumAddOns() do
			if IsAddOnLoadOnDemand(addon) and not IsAddOnLoaded(addon) then
				---A TOC metadata field allowing addons to specify code to be executed after conditional loading is successful.
				--This code will be executed during the event which triggers loading, and accepts the event and its args as varargs, which can be accessed through (...).
				--This allows you to call your addon's event handler to process the event which triggered loading.
				--If you need more code than you can fit in one TOC field, continue your string in X-AfterLoad2, X-AfterLoad3, etc.
				--@class function
				--@name [TOC] X-AfterLoad
				--@param ... Lua code to execute after loading.
				--@usage ## X-AfterLoad: MyAddon:OnEvent(...)
				--@usage ## X-AfterLoad: MyAddon:ShowFrame()
				afterfuncs[addon] = getTOCfunc(addon, "X-AfterLoad") or dummy
				---A TOC metadata field allowing addons to specify conditions for whether they should be loaded.
				--This code will be executed at PLAYER_LOGIN. If your addon needs to load sooner, or its conditional needs to be evaluated later, use X-LoadWhen.
				--If you need more code than you can fit in one TOC field, continue your string in X-LoadIf2, X-LoadIf3, etc.
				--@class function
				--@name [TOC] X-LoadIf
				--@param ... Lua code that returns some value if the addon should be loaded, and returns false or nil otherwise.
				--@usage ## X-LoadIf: return select(2,UnitClass("player")) == "WARRIOR"
				local loginhandler = getTOCfunc(addon, "X-LoadIf")
				if loginhandler and loginhandler() then
					load(addon, event, ...)
				else
					---A TOC metadata field allowing addons to specify that a LibDataBroker "launcher" dataobject should be created to trigger their loading.
					--The created launcher will load the addon upon receiving any click from the user, and pass that click along to the addon's new LDB OnClick handler, if present.
					--@class function
					--@name [TOC] X-LoadBy-Launcher
					--@param icon Path to the icon the LDB launcher should use.
					--@param name Optional name for the LDB launcher. If omitted, the name of the addon is used.
					local ldbstring = getTOCstring(addon, "X-LoadBy-Launcher")
					if ldbstring ~= "" then
						local icon, launchername = string.split(" ", ldbstring, 2)
						local name = GetAddOnInfo(addon)
						local dobj, OnClick
						OnClick = function(...)
							local ret = safeassert("Unable to load "..(GetAddOnInfo(addon))..", reason: ", LoadAddOn(addon))
							if ret and dobj.OnClick ~= OnClick then dobj.OnClick(...) end
						end
						dobj = LibStub:GetLibrary("LibDataBroker-1.1"):NewDataObject(launchername or name, { type = "launcher", icon = icon, OnClick = OnClick, tocname = name })
					end
					---A TOC metadata field allowing addons to specify events to trigger their loading.
					--Each event may optionally have a corresponding X-LoadWhen-EVENT field.
					--If you need more events than you can fit in one TOC field, continue your list in X-LoadWhen2, X-LoadWhen3, etc.
					--@class function
					--@name [TOC] X-LoadWhen
					--@param ... List of events to trigger conditional loading.
					--@usage ## X-LoadWhen: GROUP_ROSTER_UPDATE, PLAYER_ENTERING_WORLD
					--@see [TOC] X-LoadWhen-EVENT
					for event in getTOCstring(addon, "X-LoadWhen"):gmatch("[%w_]+") do
						loadhooks[event] = loadhooks[event] or {}
						---A TOC metadata field allowing addons to specify conditions for whether they should be loaded when an event listed in X-LoadWhen occurs.
						--If not specified, it is assumed that the addon always wants to load on the event.
						--This code will be executed during the specified event, and accepts the event and its args as varargs, which can be accessed through (...).
						--If you need more code than you can fit in one TOC field, continue your string in X-LoadWhen-EVENT2, X-LoadWhen-EVENT3, etc.
						--@class function
						--@name [TOC] X-LoadWhen-EVENT
						--@param ... Lua code that returns some value if the addon should be loaded, and returns false or nil otherwise.
						--@usage ## X-LoadWhen-PLAYER_ENTERING_WORLD: return (GetNumGroupMembers() > 0)
						--@see [TOC] X-LoadWhen
						loadhooks[event][addon] = getTOCfunc(addon, "X-LoadWhen-"..event) or dummy
					end
				end
			end
		end
		for event in pairs(loadhooks) do
			frame:RegisterEvent(event)
		end
	end
	if loadhooks[event] then
		for addon, handler in pairs(loadhooks[event]) do
			if IsAddOnLoaded(addon) then
				loadhooks[event][addon] = nil
			elseif  select(5, GetAddOnInfo(addon)) and handler(event, ...) then
				load(addon, event, ...)
				loadhooks[event][addon] = nil
			end
		end
		if not next(loadhooks[event]) then
			loadhooks[event] = nil
			frame:UnregisterEvent(event)
		end
	end
end)