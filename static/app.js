document.addEventListener('DOMContentLoaded', () => {
    let files = [];
    let currentIndex = 0;

    const dirInput = document.getElementById('dir-input');
    const includeCheckbox = document.getElementById('include-reviewed');
    const loadBtn = document.getElementById('load-btn');
    const singleFileInput = document.getElementById('single-file-input');
    const videoPlayer = document.getElementById('video-player');
    const nameInput = document.getElementById('name-input');
    const startInput = document.getElementById('start-input');
    const endInput = document.getElementById('end-input');
    const prevBtn = document.getElementById('prev-btn');
    const nextBtn = document.getElementById('next-btn');
    const saveBtn = document.getElementById('save-btn');
    const trimBtn = document.getElementById('trim-btn');
    const deleteBtn = document.getElementById('delete-btn');
    const indexDisplay = document.getElementById('index-display');
    const indexInput = document.getElementById('index-input');
    const jumpBtn = document.getElementById('jump-btn');
    const defaultStartPercentInput = document.getElementById('default-start-percent-input');
    const startSlider = document.getElementById('start-slider');
    const endSlider = document.getElementById('end-slider');
    const startTimeDisplay = document.getElementById('start-time-display');
    const endTimeDisplay = document.getElementById('end-time-display');
    // Centralized hotkey settings so a future UI can edit these values.
    const hotkeyConfig = {
        bindings: {
            stop: 'k',
            play: 'k',
            rewind: 'j',
            forward: 'l',
            delete: 'delete'
        },
        rewindSeconds: 10,
        forwardSeconds: 3
    };
    let isPlaybackActive = false;

    loadBtn.addEventListener('click', loadDirectory);
    document.addEventListener('keydown', handleHotkeyDown);
    prevBtn.addEventListener('click', () => navigate(-1));
    nextBtn.addEventListener('click', () => navigate(1));
    saveBtn.addEventListener('click', saveRename);
    trimBtn.addEventListener('click', trimClip);
    deleteBtn.addEventListener('click', deleteClip);
    jumpBtn.addEventListener('click', () => {
        const val = parseInt(indexInput.value, 10);
        if (!isNaN(val) && val >= 1 && val <= files.length) {
            currentIndex = val - 1;
            loadFile();
        } else {
            alert(`Please enter a number between 1 and ${files.length}`);
        }
    });
    videoPlayer.addEventListener('loadedmetadata', () => {
        const duration = videoPlayer.duration;
        startSlider.max = duration;
        endSlider.max = duration;
        startSlider.value = 0;
        endSlider.value = duration;
        startInput.value = formatTime(0);
        endInput.value = formatTime(duration);
        startTimeDisplay.textContent = formatTime(0);
        endTimeDisplay.textContent = formatTime(duration);

        const defaultStartPercent = getDefaultStartPercent();
        const startTimeSeconds = (duration * defaultStartPercent) / 100;
        videoPlayer.currentTime = Math.min(startTimeSeconds, Math.max(duration - 0.001, 0));
    });
    videoPlayer.addEventListener('play', () => {
        isPlaybackActive = true;
    });
    videoPlayer.addEventListener('pause', () => {
        isPlaybackActive = false;
    });
    videoPlayer.addEventListener('ended', () => {
        isPlaybackActive = false;
    });

    function getDefaultStartPercent() {
        const rawValue = parseFloat(defaultStartPercentInput.value);
        if (isNaN(rawValue)) {
            defaultStartPercentInput.value = 70;
            return 70;
        }
        const clamped = Math.min(100, Math.max(0, rawValue));
        defaultStartPercentInput.value = clamped;
        return clamped;
    }

    startSlider.addEventListener('input', () => {
        let startVal = parseFloat(startSlider.value);
        if (startVal > parseFloat(endSlider.value)) {
            startVal = parseFloat(endSlider.value);
            startSlider.value = startVal;
        }
        const formatted = formatTime(startVal);
        startTimeDisplay.textContent = formatted;
        startInput.value = formatted;
        videoPlayer.currentTime = startVal;
    });

    endSlider.addEventListener('input', () => {
        let endVal = parseFloat(endSlider.value);
        if (endVal < parseFloat(startSlider.value)) {
            endVal = parseFloat(startSlider.value);
            endSlider.value = endVal;
        }
        const formatted = formatTime(endVal);
        endTimeDisplay.textContent = formatted;
        endInput.value = formatted;
    });

    function normalizeHotkeyKey(rawKey) {
        return String(rawKey || '').toLowerCase();
    }

    function isTypingTarget(element) {
        if (!element) return false;
        const tag = element.tagName;
        return tag === 'INPUT' || tag === 'TEXTAREA' || element.isContentEditable;
    }

    function getHotkeyActionsByKey() {
        const actionsByKey = {};
        Object.entries(hotkeyConfig.bindings).forEach(([action, key]) => {
            const normalizedKey = normalizeHotkeyKey(key);
            if (normalizedKey) {
                if (!actionsByKey[normalizedKey]) {
                    actionsByKey[normalizedKey] = [];
                }
                actionsByKey[normalizedKey].push(action);
            }
        });
        return actionsByKey;
    }

    function resolveHotkeyAction(pressedKey) {
        const actionsByKey = getHotkeyActionsByKey();
        const actions = actionsByKey[pressedKey];
        if (!actions || actions.length === 0) return null;

        const hasPlay = actions.includes('play');
        const hasStop = actions.includes('stop');
        if (hasPlay && hasStop) {
            return isPlaybackActive ? 'stop' : 'play';
        }

        return actions[0];
    }

    function runHotkeyAction(action) {
        if (action === 'stop') {
            videoPlayer.pause();
            return;
        }

        if (action === 'play') {
            videoPlayer.play().catch(err => {
                console.error('Error starting playback from hotkey:', err);
            });
            return;
        }

        if (action === 'rewind') {
            if (!Number.isFinite(videoPlayer.currentTime)) return;
            videoPlayer.currentTime = Math.max(0, videoPlayer.currentTime - hotkeyConfig.rewindSeconds);
            return;
        }

        if (action === 'forward') {
            if (!Number.isFinite(videoPlayer.currentTime)) return;
            const target = videoPlayer.currentTime + hotkeyConfig.forwardSeconds;
            if (Number.isFinite(videoPlayer.duration)) {
                videoPlayer.currentTime = Math.min(videoPlayer.duration, target);
                return;
            }
            videoPlayer.currentTime = target;
            return;
        }

        if (action === 'delete') {
            if (files.length === 0) return;
            deleteClip();
        }
    }

    function handleHotkeyDown(event) {
        if (event.defaultPrevented) return;
        if (isTypingTarget(document.activeElement)) return;

        const pressedKey = normalizeHotkeyKey(event.key);
        const action = resolveHotkeyAction(pressedKey);
        if (!action) return;

        event.preventDefault();
        runHotkeyAction(action);
    }

    function formatTime(seconds) {
        const hrs = Math.floor(seconds / 3600);
        const mins = Math.floor((seconds % 3600) / 60);
        const secs = (seconds % 60).toFixed(3); // Keep millisecond precision
        const secsStr = parseFloat(secs) < 10 ? '0' + secs : secs;
        return (hrs > 0 ? `${hrs}:` : '') +
               (hrs > 0 ? String(mins).padStart(2, '0') : mins) + ':' +
               secsStr;
    }

    function loadDirectory() {
        // If single-file input provided, resolve path (absolute or relative to directory)
        const singleRaw = singleFileInput.value.trim();
        const dirVal = dirInput.value.trim();
        if (singleRaw) {
            let filePath = singleRaw;
            // Detect Windows absolute (e.g. C:\) or Unix absolute (/)
            const windowsAbs = /^[A-Za-z]:[\\/]/;
            if (!windowsAbs.test(singleRaw) && !singleRaw.startsWith('/')) {
                if (!dirVal) {
                    alert('Please enter a directory to resolve the filename');
                    return;
                }
                filePath = dirVal + '/' + singleRaw;
            }
            files = [filePath];
            currentIndex = 0;
            loadFile();
            return;
        }
        // Otherwise load from directory listing
        const dir = dirVal;
        if (!dir) {
            alert('Please enter a directory or paste a file path');
            return;
        }
        const includeReviewed = includeCheckbox.checked;
        fetch(`/api/files?dir=${encodeURIComponent(dir)}&include_reviewed=${includeReviewed}`)
            .then(response => response.json())
            .then(data => {
                if (data.error) {
                    alert(data.error);
                    return;
                }
                files = data.files;
                if (files.length === 0) {
                    alert('No ShadowPlay files found in this directory.');
                    return;
                }
                currentIndex = 0;
                loadFile();
            })
            .catch(err => {
                console.error(err);
                alert('Error loading files');
            });
    }

    function loadFile() {
        const path = files[currentIndex];
        videoPlayer.src = `/api/video?path=${encodeURIComponent(path)}`;
        const fname = path.split(/[\\\/]/).pop();
        const baseName = fname.replace(/\.mp4$/i, '');
        nameInput.value = baseName;
        updateIndexDisplay();
    }

    function updateIndexDisplay() {
        indexDisplay.textContent = `${currentIndex + 1}/${files.length}`;
        indexInput.value = '';
    }

    function navigate(direction) {
        if (files.length === 0) return;
        const newIndex = currentIndex + direction;
        if (newIndex >= 0 && newIndex < files.length) {
            currentIndex = newIndex;
            loadFile();
        }
    }

    function saveRename() {
        videoPlayer.pause();
        videoPlayer.removeAttribute('src');
        videoPlayer.load();
        const origPath = files[currentIndex];
        const newName = nameInput.value.trim();
        if (!newName) {
            alert('Name cannot be empty');
            loadFile();
            return;
        }
        const payload = {
            action: 'keep',
            path: origPath,
            new_name: newName
        };
        fetch('/api/action', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify(payload)
        })
        .then(response => response.json())
        .then(data => {
            if (data.error) {
                alert(data.error);
                loadFile();
                return;
            }
            // Update path in list and reload file
            files[currentIndex] = data.new_path;
            loadFile();
        })
        .catch(err => {
            console.error(err);
            alert('Error saving changes');
            loadFile();
        });
    }

    function trimClip() {
        videoPlayer.pause();
        videoPlayer.removeAttribute('src');
        videoPlayer.load();
        const origPath = files[currentIndex];
        const newName = nameInput.value.trim();
        const startTime = startInput.value.trim();
        const endTime = endInput.value.trim();
        if (!newName) {
            alert('Name cannot be empty for trim');
            loadFile();
            return;
        }
        if (!startTime) {
            alert('Please enter a start time');
            loadFile();
            return;
        }
        const payload = {
            action: 'trim',
            path: origPath,
            new_name: newName,
            start: startTime,
            end: endTime
        };
        fetch('/api/action', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify(payload)
        })
        .then(response => response.json())
        .then(data => {
            if (data.error) {
                alert(data.error);
                loadFile();
                return;
            }
            // Replace current file with trimmed version
            files[currentIndex] = data.new_path;
            loadFile();
        })
        .catch(err => {
            console.error(err);
            alert('Error trimming clip');
            loadFile();
        });
    }

    function deleteClip() {
        videoPlayer.pause();
        videoPlayer.removeAttribute('src');
        videoPlayer.load();
        const origPath = files[currentIndex];
        if (!confirm('Are you sure you want to delete this clip?')) {
            loadFile();
            return;
        }
        const payload = { action: 'delete', path: origPath };
        fetch('/api/action', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify(payload)
        })
        .then(response => response.json())
        .then(data => {
            if (data.error) {
                alert(data.error);
                loadFile();
                return;
            }
            // Remove this file and load next
            files.splice(currentIndex, 1);
            if (currentIndex >= files.length) {
                currentIndex = files.length - 1;
            }
            if (files.length > 0) {
                loadFile();
            } else {
                videoPlayer.src = '';
                nameInput.value = '';
                alert('No more files to review.');
            }
        })
        .catch(err => {
            console.error(err);
            alert('Error deleting clip');
            loadFile();
        });
    }
}); 