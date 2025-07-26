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

    // --- Dynamic GitHub Release Download Links ---
    async function fetchLatestRelease() {
      const apiUrl = 'https://api.github.com/repos/supastishn/mcu-sim/releases/latest';
      try {
        const response = await fetch(apiUrl);
        if (!response.ok) throw new Error(`GitHub API error: ${response.status}`);
        return response.json();
      } catch (error) {
        console.error('Failed to fetch release info:', error);
        throw error;
      }
    }

    function findAsset(release, patterns) {
      const assets = release.assets || [];
      for (const asset of assets) {
        const name = asset.name.toLowerCase();
        if (patterns.some(pattern => name.includes(pattern))) {
          return asset;
        }
      }
      return null;
    }

    function updateDownloadUI(platform, asset) {
      const element = document.getElementById(`${platform}-download`);
      if (!element || !asset) return;
      element.href = asset.browser_download_url;
      const button = element.querySelector('.button');
      button.innerHTML = 'Download';
    }

    async function initDownloadLinks() {
      const warningElement = document.getElementById('download-warning');
      try {
        const release = await fetchLatestRelease();
        warningElement.style.display = 'none';
        updateDownloadUI('windows', findAsset(release, ['windows', '.exe']));
        updateDownloadUI('android', findAsset(release, ['android', '.apk']));
        updateDownloadUI('linux', findAsset(release, ['linux', '.zip']));
      } catch (error) {
        warningElement.style.display = 'block';
        warningElement.innerHTML = `
          <p style="color:var(--color-danger);font-weight:bold;text-align:center;">
            Unable to load downloads: ${error.message}. 
            <a href="https://github.com/supastishn/mcu-sim/releases" target="_blank">
              Visit Releases page directly
            </a>
          </p>
        `;
        warningElement.style.color = 'var(--color-danger)';
      }
    }

    // Initialize dynamic download links
    initDownloadLinks();
});
