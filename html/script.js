let config = null
let quick = []
let selected = null
let selectedPayment = null

const $ = (id) => document.getElementById(id)

const formatTime = (sec) => {
    if (sec <= 0) return '0s'
    if (sec >= 60) return Math.floor(sec / 60) + 'm ' + (sec % 60) + 's'
    return sec + 's'
}

const buildQuickList = () => {
    const ql = $('quickList')
    ql.innerHTML = ''
    quick.forEach((item, idx) => {
        const b = document.createElement('button')
        b.innerText = '📍 ' + item.name
        b.onclick = () => selectQuick(idx)
        ql.appendChild(b)
    })
}

const selectQuick = (idx) => {
    const buttons = document.querySelectorAll('#quickList button'); 
    buttons.forEach(b => b.classList.remove('active')); 
    if (buttons[idx]) buttons[idx].classList.add('active');
    fetch(`https://${GetParentResourceName()}/preview`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify({ quickIndex: idx + 1 })
    })
        .then(r => r.json())
        .then(resp => {
            if (!resp.success) {
                $('info').innerText = 'Error: ' + resp.reason
                return
            }
            $('fareDisplay').innerText = '$' + resp.fare
            $('etaDisplay').innerText = 'Est. Time: ' + formatTime(resp.eta)
            selected = { quickIndex: idx + 1, preset: resp.preset, fare: resp.fare, eta: resp.eta }
            $('requestTaxi').disabled = false
        })
}

const useWaypoint = () => {
    fetch(`https://${GetParentResourceName()}/preview`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify({ useWaypoint: true })
    })
        .then(r => r.json())
        .then(resp => {
            if (!resp.success) {
                $('info').innerText = 'Error: ' + resp.reason
                return
            }
            $('fareDisplay').innerText = '$' + resp.fare
            $('etaDisplay').innerText = 'Est. Time: ' + formatTime(resp.eta)
            selected = { useWaypoint: true, fare: resp.fare, eta: resp.eta }
            $('requestTaxi').disabled = false
        })
}

const requestTaxi = () => {
    if (!selected) return
    const mode = $('modeSelect').value
    const payload = Object.assign({ mode: mode }, selected)
    fetch(`https://${GetParentResourceName()}/requestTaxi`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload)
    })
        .then(r => r.json())
        .then(resp => {
            if (!resp.success) {
                $('info').innerText = 'Error: ' + resp.reason
            }
        })
}

const closeUI = () => {
    fetch(`https://${GetParentResourceName()}/close`, { method: 'POST' })
}

const setPayment = (method) => {
    selectedPayment = method
    const bankBtn = $('bankOption')
    const cashBtn = $('cashOption')
    
    if (bankBtn) bankBtn.classList.toggle('selected', method === 'bank')
    if (cashBtn) cashBtn.classList.toggle('selected', method === 'cash')
    
    const confirmBtn = $('confirmBtn')
    if (confirmBtn) {
        confirmBtn.disabled = false
        const icon = $('confirmIcon') || (() => {
            const span = document.createElement('span')
            span.id = 'confirmIcon'
            span.style.marginRight = '6px'
            return span
        })()
        icon.innerText = method === 'bank' ? '🏦' : '💵'
        confirmBtn.classList.remove('bank', 'cash')
        confirmBtn.classList.add(method)
        confirmBtn.innerHTML = ''
        confirmBtn.appendChild(icon)
        confirmBtn.appendChild(document.createTextNode(' Confirm – Pay with ' + (method === 'bank' ? 'Bank' : 'Cash')))
    }
    
    try {
        fetch(`https://${GetParentResourceName()}/playSound`, { method: 'POST' })
    } catch (e) {}
}

const confirmRide = () => {
    if (!selectedPayment) {
        $('info').innerText = 'Please select a payment method first.'
        return
    }
    const mode = $('modeSelect')?.value || 'watch'
    const payload = Object.assign({ mode: mode, payment: selectedPayment }, selected || {})
    fetch(`https://${GetParentResourceName()}/confirmRide`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload)
    })
        .then(r => r.json())
        .then(resp => {
            if (!resp.success) {
                $('info').innerText = 'Error: ' + resp.reason
                return
            }
            $('confirmModal').classList.add('hidden')
            fetch(`https://${GetParentResourceName()}/close`, { method: 'POST' })
        })
}

// Window message handler
window.addEventListener('message', (e) => {
    const d = e.data
    
    if (d.action === 'openUI') {
        config = d.config || config
        quick = config.PresetLocations || quick
        buildQuickList()
        $('fareDisplay').innerText = '$0'
        $('etaDisplay').innerText = 'Est. Time: --'
        $('info').innerText = ''
        $('requestTaxi').disabled = true
        document.body.style.display = 'block'
        $('app').setAttribute('aria-hidden', 'false')
    }

    if (d.action === 'hideUI') {
        document.body.style.display = 'none'
        $('app').setAttribute('aria-hidden', 'true')
    }

    if (d.action === 'updateHUD') {
        const eta = d.eta || 0
        const distance = d.distance || 0
        const fare = d.fare || 0
        $('hud-line').innerText = `🚕 ETA: ${formatTime(eta)} | Dist: ${distance} m | Fare: $${fare}`
        $('taxi-hud').classList.remove('hidden')
        const pct = Math.max(0, Math.min(100, 100 - (distance / 1000) * 100))
        $('hud-bar').style.width = pct + '%'
    }

    if (d.action === 'clearHUD') {
        $('taxi-hud').classList.add('hidden')
        $('hud-bar').style.width = '0%'
    }

    if (d.action === 'farePopup') {
        $('fare-amount').innerText = '$' + (d.fare || 0)
        $('fare-popup').classList.remove('hidden')
        setTimeout(() => $('fare-popup').classList.add('hidden'), 5000)
    }

    if (d.action === 'openConfirm') {
        const preview = d.data || {}
        const mode = preview.mode || 'watch'
        const destName = (preview.preset || preview.useWaypoint) ? (preview.preset || 'Waypoint') : 'Destination'
        $('confirmBody').innerHTML = `
            <strong>${destName}</strong><br>
            Fare: $${preview.fare || '--'}<br>
            ETA: ${formatTime(preview.eta || 0)}
        `
        $('confirmModal').classList.remove('hidden')
        if (config && config.SoundEffects) {
            fetch(`https://${GetParentResourceName()}/playSound`, { method: 'POST' })
        }
    }
})

// Initialize event listeners after DOM ready
setTimeout(() => {
    const useWaypointBtn = $('useWaypoint')
    const openQuickBtn = $('openQuick')
    const requestTaxiBtn = $('requestTaxi')
    const closeBtnEl = $('closeBtn')
    const confirmBtnEl = $('confirmBtn')
    const cancelBtnEl = $('cancelBtn')
    const cashOption = $('cashOption')
    const bankOption = $('bankOption')

    if (useWaypointBtn) useWaypointBtn.onclick = useWaypoint
    if (openQuickBtn) openQuickBtn.onclick = buildQuickList
    if (requestTaxiBtn) requestTaxiBtn.onclick = requestTaxi
    if (closeBtnEl) closeBtnEl.onclick = closeUI
    if (confirmBtnEl) confirmBtnEl.onclick = confirmRide
    if (cancelBtnEl) cancelBtnEl.onclick = () => {
        $('confirmModal').classList.add('hidden')
        fetch(`https://${GetParentResourceName()}/playSound`, { method: 'POST' })
    }
    if (cashOption) cashOption.onclick = () => setPayment('cash')
    if (bankOption) bankOption.onclick = () => setPayment('bank')

    setPayment('bank')
}, 200)
