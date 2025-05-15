document.addEventListener('DOMContentLoaded', function() {
    
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

    // Handle horizontal scrolling with keyboard for components section
    const componentsScroll = document.querySelector('.components-scroll');
    if (componentsScroll) {
        // Add arrow key navigation for the component scroll
        document.addEventListener('keydown', function(e) {
            if (document.activeElement === componentsScroll || componentsScroll.contains(document.activeElement)) {
                if (e.key === 'ArrowRight') {
                    componentsScroll.scrollBy({ left: 220, behavior: 'smooth' });
                    e.preventDefault();
                } else if (e.key === 'ArrowLeft') {
                    componentsScroll.scrollBy({ left: -220, behavior: 'smooth' });
                    e.preventDefault();
                }
            }
        });

        // Make components section keyboard focusable
        componentsScroll.tabIndex = 0;
        
        // Add scroll buttons for mobile/desktop users
        const componentsContainer = document.querySelector('.components-container');
        const scrollLeftBtn = document.createElement('button');
        scrollLeftBtn.className = 'scroll-btn scroll-left';
        scrollLeftBtn.innerHTML = '<i class="fas fa-chevron-left"></i>';
        
        const scrollRightBtn = document.createElement('button');
        scrollRightBtn.className = 'scroll-btn scroll-right'; 
        scrollRightBtn.innerHTML = '<i class="fas fa-chevron-right"></i>';
        
        componentsContainer.appendChild(scrollLeftBtn);
        componentsContainer.appendChild(scrollRightBtn);
        
        scrollLeftBtn.addEventListener('click', () => {
            componentsScroll.scrollBy({ left: -220, behavior: 'smooth' });
        });
        
        scrollRightBtn.addEventListener('click', () => {
            componentsScroll.scrollBy({ left: 220, behavior: 'smooth' });
        });
    }
});
