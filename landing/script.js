document.addEventListener("DOMContentLoaded", () => {
  initTypingDemo();
  initBillingToggle();
  initScrollAnimations();
  initMobileMenu();
  initSmoothScroll();
});

function initTypingDemo() {
  const outputText = document.querySelector(".output-text");
  const cursor = document.querySelector(".output-cursor");
  if (!outputText || !cursor) return;

  const phrases = [
    "声で入力すると、タイピングより速いですね。",
    "今日の会議の議事録を作成してください。",
    "お疲れ様です。明日の予定を確認させてください。",
    "このプロジェクトの進捗状況を報告します。",
  ];

  let phraseIndex = 0;
  let charIndex = 0;
  let isDeleting = false;
  let isPaused = false;

  function type() {
    const currentPhrase = phrases[phraseIndex];

    if (isPaused) {
      setTimeout(type, 50);
      return;
    }

    if (isDeleting) {
      outputText.textContent = currentPhrase.substring(0, charIndex - 1);
      charIndex--;

      if (charIndex === 0) {
        isDeleting = false;
        phraseIndex = (phraseIndex + 1) % phrases.length;
        isPaused = true;
        setTimeout(() => {
          isPaused = false;
        }, 500);
      }
    } else {
      outputText.textContent = currentPhrase.substring(0, charIndex + 1);
      charIndex++;

      if (charIndex === currentPhrase.length) {
        isPaused = true;
        setTimeout(() => {
          isPaused = false;
          isDeleting = true;
        }, 2000);
      }
    }

    const speed = isDeleting ? 30 : 60;
    setTimeout(type, speed);
  }

  setTimeout(type, 1000);
}

function initBillingToggle() {
  const toggleBtns = document.querySelectorAll(".toggle-btn");
  const priceAmounts = document.querySelectorAll(".price-amount");

  toggleBtns.forEach((btn) => {
    btn.addEventListener("click", () => {
      toggleBtns.forEach((b) => b.classList.remove("active"));
      btn.classList.add("active");

      const billing = btn.dataset.billing;

      priceAmounts.forEach((price) => {
        const amount = price.dataset[billing];
        price.textContent = `$${amount}`;

        price.style.transform = "scale(0.9)";
        price.style.opacity = "0.5";

        requestAnimationFrame(() => {
          price.style.transition = "all 0.2s ease";
          price.style.transform = "scale(1)";
          price.style.opacity = "1";
        });
      });
    });
  });
}

function initScrollAnimations() {
  const observerOptions = {
    root: null,
    rootMargin: "0px",
    threshold: 0.1,
  };

  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add("animate-in");
        observer.unobserve(entry.target);
      }
    });
  }, observerOptions);

  const animateElements = document.querySelectorAll(
    ".feature-card, .pricing-card, .faq-item, .section-header",
  );

  animateElements.forEach((el, index) => {
    el.style.opacity = "0";
    el.style.transform = "translateY(30px)";
    el.style.transition = `all 0.6s ease ${index * 0.1}s`;
    observer.observe(el);
  });

  const style = document.createElement("style");
  style.textContent = `
    .animate-in {
      opacity: 1 !important;
      transform: translateY(0) !important;
    }
  `;
  document.head.appendChild(style);
}

function initMobileMenu() {
  const mobileMenuBtn = document.querySelector(".mobile-menu");
  const navLinks = document.querySelector(".nav-links");

  if (!mobileMenuBtn || !navLinks) return;

  const navLinksClone = navLinks.cloneNode(true);
  navLinksClone.classList.add("mobile-nav");
  navLinksClone.style.cssText = `
    display: none;
    position: fixed;
    top: 70px;
    left: 0;
    right: 0;
    background: rgba(10, 10, 10, 0.98);
    backdrop-filter: blur(20px);
    padding: 2rem;
    flex-direction: column;
    gap: 1.5rem;
    border-bottom: 1px solid var(--color-border);
    z-index: 999;
  `;

  document.body.appendChild(navLinksClone);

  let isOpen = false;

  mobileMenuBtn.addEventListener("click", () => {
    isOpen = !isOpen;

    if (isOpen) {
      navLinksClone.style.display = "flex";
      mobileMenuBtn.classList.add("active");
    } else {
      navLinksClone.style.display = "none";
      mobileMenuBtn.classList.remove("active");
    }
  });

  navLinksClone.querySelectorAll("a").forEach((link) => {
    link.addEventListener("click", () => {
      isOpen = false;
      navLinksClone.style.display = "none";
      mobileMenuBtn.classList.remove("active");
    });
  });

  const menuStyle = document.createElement("style");
  menuStyle.textContent = `
    .mobile-menu.active span:first-child {
      transform: rotate(45deg) translate(5px, 5px);
    }
    .mobile-menu.active span:last-child {
      transform: rotate(-45deg) translate(5px, -5px);
    }
    .mobile-nav a {
      font-size: 1.1rem !important;
      color: var(--color-text) !important;
    }
    .mobile-nav .nav-cta {
      text-align: center;
    }
  `;
  document.head.appendChild(menuStyle);
}

function initSmoothScroll() {
  document.querySelectorAll('a[href^="#"]').forEach((anchor) => {
    anchor.addEventListener("click", function (e) {
      e.preventDefault();
      const targetId = this.getAttribute("href");
      if (targetId === "#") return;

      const target = document.querySelector(targetId);
      if (target) {
        const headerOffset = 80;
        const elementPosition = target.getBoundingClientRect().top;
        const offsetPosition = elementPosition + window.pageYOffset - headerOffset;

        window.scrollTo({
          top: offsetPosition,
          behavior: "smooth",
        });
      }
    });
  });
}

const header = document.querySelector(".header");
let lastScroll = 0;

window.addEventListener("scroll", () => {
  const currentScroll = window.pageYOffset;

  if (currentScroll > 100) {
    header.style.boxShadow = "0 4px 20px rgba(0, 0, 0, 0.3)";
  } else {
    header.style.boxShadow = "none";
  }

  lastScroll = currentScroll;
});

const waveformContainer = document.querySelector(".waveform-container");
if (waveformContainer) {
  waveformContainer.addEventListener("mouseenter", () => {
    const waveBars = waveformContainer.querySelectorAll(".wave-bar");
    waveBars.forEach((bar) => {
      bar.style.animationDuration = "0.6s";
    });
  });

  waveformContainer.addEventListener("mouseleave", () => {
    const waveBars = waveformContainer.querySelectorAll(".wave-bar");
    waveBars.forEach((bar) => {
      bar.style.animationDuration = "1.2s";
    });
  });
}
