document.addEventListener('DOMContentLoaded', function() {
    // Tab switching functionality
    const tabs = document.querySelectorAll('.tab');
    tabs.forEach(tab => {
        tab.addEventListener('click', function() {
            // Remove active class from all tabs
            tabs.forEach(t => t.classList.remove('active'));
            // Add active class to clicked tab
            this.classList.add('active');
        });
    });

    // Simulator controls
    const playButton = document.querySelector('.control-button:nth-child(1)');
    const pauseButton = document.querySelector('.control-button:nth-child(2)');
    const stepButton = document.querySelector('.control-button:nth-child(3)');
    const resetButton = document.querySelector('.control-button:nth-child(4)');
    
    let isRunning = false;
    let ledState = true;
    let interval;
    
    playButton.addEventListener('click', function() {
        if (!isRunning) {
            isRunning = true;
            interval = setInterval(toggleLED, 500);
        }
    });
    
    pauseButton.addEventListener('click', function() {
        isRunning = false;
        clearInterval(interval);
    });
    
    stepButton.addEventListener('click', function() {
        if (!isRunning) {
            toggleLED();
        }
    });
    
    resetButton.addEventListener('click', function() {
        isRunning = false;
        clearInterval(interval);
        ledState = false;
        updateLEDState();
    });
    
    function toggleLED() {
        ledState = !ledState;
        updateLEDState();
    }
    
    function updateLEDState() {
        const led = document.querySelector('.led');
        const pb5State = document.querySelector('.pin:nth-child(6) .pin-state');
        
        if (ledState) {
            led.classList.add('on');
            pb5State.textContent = '1';
            pb5State.classList.remove('low');
            pb5State.classList.add('high');
        } else {
            led.classList.remove('on');
            pb5State.textContent = '0';
            pb5State.classList.remove('high');
            pb5State.classList.add('low');
        }
    }
    
    // Smooth scrolling for anchor links
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function(e) {
            e.preventDefault();
            const targetId = this.getAttribute('href');
            if (targetId === '#') return;
            
            const targetElement = document.querySelector(targetId);
            if (targetElement) {
                targetElement.scrollIntoView({
                    behavior: 'smooth'
                });
            }
        });
    });
});
