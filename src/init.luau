--------------------------------------------------------------------------------
--
-- Remote-Image-Library (./init.luau)
--
-- plainenglish
-- December 2023
--
-- A library to create an EditableImage instance from a remote PNG url.
-- Utilises MaximumADHD's Roblox-PNG-Library to parse the png data, packed into.
-- a single file for simplicities sake.
-- (https://github.com/MaximumADHD/Roblox-PNG-Library/tree/master)
--
--------------------------------------------------------------------------------

local VERSION = "v1.0.0";
local HTTP_QUEUE_REQUESTS_PER_SEC = 2;
local PRINT_LEADER = "[Remote-Image-Library]: ";

local http_service = game:GetService("HttpService");
local run_service = game:GetService("RunService");

local png = require(script.png);
export type png = typeof(png.new());

local is_server = run_service:IsServer();
local builtin = {};
local http_queue = {};
local queue_active = false;


--------------------------------------------------------------------------------
--  
-- http_get_async
--
-- Performs a queued HTTP request.
--
--------------------------------------------------------------------------------
function http_get_async(url : string) : string
	if not queue_active then
		queue_active = true;
		task.spawn(function()
			while task.wait(HTTP_QUEUE_REQUESTS_PER_SEC) do
				local req = http_queue[1];

				if not req then
					continue;
				end
				
				local success, res = pcall(function()
					return http_service:GetAsync(req.url);
				end);

				req.fufil({
					success = success,
					data = res,
				});

				table.remove(http_queue, 1);
			end
		end);
	end
	
	local data;

	table.insert(http_queue, {
		fufil = function(res)
			if res.success then
				data = res.data;
			else
				error(PRINT_LEADER .. "Get failed with: " .. data.data);
			end
		end,
		url = url
	});

	repeat task.wait(); until data;
	return data;
end

--------------------------------------------------------------------------------
--  
-- get_pixel_array
--
-- Returns a pixel array from a PNG object.
--
--------------------------------------------------------------------------------
function get_pixel_array(image : png) : {number}
	local arr = {};

	for y = 1, image.Height do
		for x = 1, image.Width do
			local colour, alpha = image:GetPixel(x, y);

			table.insert(arr, colour.R);
			table.insert(arr, colour.G);
			table.insert(arr, colour.B);
			table.insert(arr, alpha);
		end
	end

	return arr;
end


--------------------------------------------------------------------------------
--  
-- url_to_png_obj
--
-- Creates a png object from the provided url.
--
--------------------------------------------------------------------------------
function url_to_png_obj(url : string) : png
	local raw = _G["REMOTE_IMG_CUSTOM_GET"] or http_get_async(url);    
	return png.new(raw);
end


--------------------------------------------------------------------------------
--  
-- create_image_from_array
--
-- Creates an EditableImage from a pixel array.
--
--------------------------------------------------------------------------------
function create_image_from_array(pixel_array : string, width : number, height : number) : EditableImage
	local editable_img = Instance.new("EditableImage");
	editable_img.Size = Vector2.new(width, height);

	editable_img:WritePixels(
		Vector2.new(0, 0),
		Vector2.new(width, height),
		pixel_array
	);

	return editable_img;
end


--------------------------------------------------------------------------------
--  
-- create_image
--
-- Creates an EditableImage from a png url.
--
--------------------------------------------------------------------------------
function create_image(url : string) : EditableImage
	if is_server then
		local image = url_to_png_obj(url);
		local pixel_array = get_pixel_array(image);
	
		return create_image_from_array(pixel_array, image.Width, image.Height);
	else
		local remote = script:WaitForChild("communicator");
		local data = remote:InvokeServer(url);
		assert(data, PRINT_LEADER .. "Request unauthorised.")
		local pixel_array, width, height = unpack(data);

		return create_image_from_array(pixel_array, width, height);
	end
end


--------------------------------------------------------------------------------
--  
-- create_image_from_string
--
-- Creates an EditableImage from a binary string.
--
--------------------------------------------------------------------------------
function create_image_from_string(data : string | buffer) : EditableImage
	if typeof(data) == "buffer" then
		data = buffer.tostring(data);
	end
	
	local image = png.new(data);
	local pixel_array = get_pixel_array(image);

	return create_image_from_array(pixel_array, image.Width, image.Height);
end


--------------------------------------------------------------------------------
--  
-- serve
--
-- Allows clients to execute 'create_image'
--
--------------------------------------------------------------------------------
function serve(auth_func : (Player, string) -> (boolean)?) : nil
	if not auth_func then
		warn(
			PRINT_LEADER
			.. "No auth_func provided, all users have the ability to"
			.. " use the create_image function. Pass 'builtin.allow_all'"
			.. " into 'serve()' to silence this message."
		);
	end
	
	local remote = Instance.new("RemoteFunction");
	remote.Name = "communicator";
	remote.Parent = script;

	-- string.sub(url, 0, 20) == "https://i.imgur.com/"

	remote.OnServerInvoke = function(player : Player, url : string) : {number}?
		if auth_func then		
			if not auth_func(player, url) then
				return nil;	
			end
		end

		local img = url_to_png_obj(url);

		return {
			get_pixel_array(img),
			img.Width,
			img.Height
		};
	end;

	return nil;
end


--------------------------------------------------------------------------------
--  
-- builtin.protocols
--
-- Returns true if the provided url is one of the passed protocols.
--
--------------------------------------------------------------------------------
function builtin.protocols(url : string, protocols : {string}) : boolean
	local protocol = url:split("://")[1];
	return table.find(protocols, protocol) ~= nil;
end


--------------------------------------------------------------------------------
--  
-- builtin.hosts
--
-- Returns true if the provided url is one of the passed protocols.
--
--------------------------------------------------------------------------------
function builtin.hosts(url : string, hosts : {string}) : boolean
	local host = url:split("://")[2]:split("/")[1];
	return table.find(hosts, host) ~= nil;
end


--------------------------------------------------------------------------------
--  
-- builtin.user_ids
--
-- Returns true if the provided player has one of the passed user_ids,
--
--------------------------------------------------------------------------------
function builtin.user_ids(player : Player, user_ids : {number}) : boolean
	return table.find(user_ids, player.UserId) ~= nil;
end


--------------------------------------------------------------------------------
--  
-- builtin.paths
--
-- Returns true if the provided player has one of the passed user_ids,
--
--------------------------------------------------------------------------------
function builtin.paths(url : string, paths : {string}) : boolean
	local protocol_len = #(url:split("://")[1]) + 3;
	local host_len = #(url:split("://")[2]:split("/")[1]) + 2;

	return table.find(paths, string.sub(url, protocol_len + host_len)) ~= nil;
end


--------------------------------------------------------------------------------
--  
-- builtin.allow_all
--
-- Always returns true.
--
--------------------------------------------------------------------------------
function builtin.allow_all() : boolean
	return true;
end


--------------------------------------------------------------------------------
-- Export:

return {
	create_image = create_image,
	serve = serve,
	create_image_from_array = create_image_from_array,
	create_image_from_string = create_image_from_string,
	builtin = builtin,
	http_get_async = http_get_async,
	version = VERSION
}