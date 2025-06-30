document.addEventListener('DOMContentLoaded', () => {
    let files = [];
    let currentIndex = 0;

    const dirInput = document.getElementById('dir-input');
    const loadBtn = document.getElementById('load-btn');
    const videoPlayer = document.getElementById('video-player');
    const nameInput = document.getElementById('name-input');
    const startInput = document.getElementById('start-input');
    const endInput = document.getElementById('end-input');
    const prevBtn = document.getElementById('prev-btn');
    const nextBtn = document.getElementById('next-btn');
    const saveBtn = document.getElementById('save-btn');
    const trimBtn = document.getElementById('trim-btn');
    const deleteBtn = document.getElementById('delete-btn');

    loadBtn.addEventListener('click', loadDirectory);
    prevBtn.addEventListener('click', () => navigate(-1));
    nextBtn.addEventListener('click', () => navigate(1));
    saveBtn.addEventListener('click', saveRename);
    trimBtn.addEventListener('click', trimClip);
    deleteBtn.addEventListener('click', deleteClip);

    function loadDirectory() {
        const dir = dirInput.value.trim();
        if (!dir) {
            alert('Please enter a directory');
            return;
        }
        fetch(`/api/files?dir=${encodeURIComponent(dir)}`)
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
        const origPath = files[currentIndex];
        const newName = nameInput.value.trim();
        if (!newName) {
            alert('Name cannot be empty');
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
                return;
            }
            // Update path in list and reload file
            files[currentIndex] = data.new_path;
            loadFile();
        })
        .catch(err => {
            console.error(err);
            alert('Error saving changes');
        });
    }

    function trimClip() {
        const origPath = files[currentIndex];
        const newName = nameInput.value.trim();
        const startTime = startInput.value.trim();
        const endTime = endInput.value.trim();
        if (!newName) {
            alert('Name cannot be empty for trim');
            return;
        }
        if (!startTime) {
            alert('Please enter a start time');
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
                return;
            }
            // Replace current file with trimmed version
            files[currentIndex] = data.new_path;
            loadFile();
        })
        .catch(err => {
            console.error(err);
            alert('Error trimming clip');
        });
    }

    function deleteClip() {
        const origPath = files[currentIndex];
        if (!confirm('Are you sure you want to delete this clip?')) return;
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
        });
    }
}); 