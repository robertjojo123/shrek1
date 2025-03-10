local monitor = peripheral.find("monitor")
if not monitor then
    error("No monitor found! Attach a monitor to use this script.", 0)
end

monitor.setBackgroundColor(colors.black)
monitor.clear()

-- Base video URL (Latest repo version)
local baseURL = "https://raw.githubusercontent.com/robertjojo123/shrek1/refs/heads/main/video_part_"

-- Identify quadrant based on computer label
local quadrant = os.getComputerLabel()
local quadrantIndex = tonumber(string.sub(quadrant, -1))
if not quadrantIndex or quadrantIndex < 0 or quadrantIndex > 3 then
    error("Error: Computer label must be 'comp0', 'comp1', 'comp2', or 'comp3'.", 0)
end

-- Frame timing constants
local firstVideoDuration = 38000  -- 38s
local otherVideoDuration = 45000  -- 45s
local frameInterval = 200         -- 200ms per frame (5 FPS)
local downloadTime = 0            -- Tracks time spent downloading
local frameWidth, frameHeight = 246, 120  -- New quadrant resolution
local globalStartTime = nil       -- Synchronization timestamp

function getMovieURL(index)
    return baseURL .. index .. "_q" .. quadrantIndex .. ".nfv"
end

function downloadVideo(index, filename)
    local url = getMovieURL(index)
    print("Downloading:", url)

    local startTime = os.epoch("utc")
    local response = http.get(url)

    if response then
        local file = fs.open(filename, "wb")
        file.write(response.readAll())
        file.close()
        response.close()
        downloadTime = os.epoch("utc") - startTime  -- Track download time
        return true
    else
        print("Failed to download:", filename)
        return false
    end
end

function loadVideo(videoFile)
    if not fs.exists(videoFile) then
        print("Error: Video file not found - " .. videoFile)
        return nil, nil
    end

    local videoData = {}
    for line in io.lines(videoFile) do
        table.insert(videoData, line)
    end
    local resolution = { videoData[1]:match("(%d+) (%d+)") }
    table.remove(videoData, 1)  -- Remove header
    return videoData, resolution
end

function playVideo(videoFile, videoStartTime, videoIndex)
    local videoData, resolution = loadVideo(videoFile)
    if not videoData or not resolution then
        print("Error loading video data.")
        return false
    end

    local frameIndex = 1  -- Reset frame index for new video part
    local videoEndTime = videoStartTime + (videoIndex == 1 and firstVideoDuration or otherVideoDuration)
    local previousFrame = {}

    -- **Frame Synchronization**
    local expectedOffset = os.epoch("utc") - globalStartTime
    local frameCorrection = math.floor(expectedOffset / frameInterval)
    frameIndex = frameIndex + (frameCorrection * frameHeight)

    while os.epoch("utc") < videoEndTime do
        local frameStartTime = os.epoch("utc")

        -- **Extract frame data**
        local frameLines = {}
        for i = 1, frameHeight do
            if frameIndex + i > #videoData then break end
            table.insert(frameLines, videoData[frameIndex + i])
        end

        -- **Render frame only if valid**
        if #frameLines > 0 then
            local imageData = paintutils.parseImage(table.concat(frameLines, "\n"))
            term.redirect(monitor)
            monitor.clear()

            -- **Flicker Prevention: Only update changed pixels**
            for y = 1, #imageData do
                for x = 1, #imageData[y] do
                    if not previousFrame[y] or previousFrame[y][x] ~= imageData[y][x] then
                        paintutils.drawPixel(x, y, imageData[y][x])
                    end
                end
            end

            previousFrame = imageData
            term.redirect(term.native())
        end

        frameIndex = frameIndex + frameHeight
        if frameIndex > #videoData then break end

        -- **Ensure exact 200ms frame timing**
        local elapsedTime = os.epoch("utc") - frameStartTime
        local sleepTime = (frameInterval - elapsedTime - (downloadTime / frameHeight)) / 1000
        if sleepTime > 0 then os.sleep(sleepTime) end
    end

    return true  -- Indicate successful playback
end

function playMovie()
    local videoIndex = 1
    globalStartTime = os.epoch("utc")

    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    
    print("Preparing to play movie...")
    os.sleep(0.75)  -- **750ms delay before first video starts**

    while true do
        print("Downloading video part:", videoIndex)
        if not downloadVideo(videoIndex, "/current_video.nfv") then 
            print("No more video parts available, stopping playback.")
            break 
        end

        local nextIndex = videoIndex + 1
        local nextFile = "/next_video.nfv"

        print("Pre-downloading next part:", nextIndex)
        if not downloadVideo(nextIndex, nextFile) then
            print("No more videos available, ending playback after this part.")
            nextFile = nil
        end

        print("Playing video part:", videoIndex)
        local success = playVideo("/current_video.nfv", globalStartTime, videoIndex)
        fs.delete("/current_video.nfv")

        if nextFile and fs.exists(nextFile) and success then
            fs.move(nextFile, "/current_video.nfv")
            videoIndex = nextIndex
            globalStartTime = os.epoch("utc")  -- Reset time for new video
        else
            break
        end
    end
end

print("Waiting for redstone signal...")

while true do
    if redstone.getInput("top") or redstone.getInput("bottom") or redstone.getInput("left") or redstone.getInput("right") or redstone.getInput("front") or redstone.getInput("back") then
        print("Redstone signal detected! Starting movie playback...")
        playMovie()
    end
    os.sleep(0.1)
end
