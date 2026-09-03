(() => {
  document.documentElement.classList.add("js");
  const nav = document.querySelector(".nav");
  const toggle = document.querySelector(".menu-toggle");
  const overlay = document.querySelector(".overlay");
  const lightbox = document.querySelector(".lightbox");
  const lightboxImg = lightbox?.querySelector("img");
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // The reading progress bar has a pure-CSS implementation driven by a scroll
  // timeline. Where that runs, the browser owns the transform and JavaScript
  // must keep its hands off it; this only takes over when it does not, or when
  // reduced motion has disabled the animation that carries it.
  const progress = document.querySelector(".reading-progress__bar");
  const cssDrivesProgress =
    !reduce &&
    typeof CSS !== "undefined" &&
    typeof CSS.supports === "function" &&
    CSS.supports("animation-timeline", "scroll()");

  const setProgress = () => {
    if (!progress) return;
    const doc = document.documentElement;
    const scrollable = doc.scrollHeight - window.innerHeight;
    // A page shorter than the viewport has nothing to report, and dividing by
    // that zero would write NaN into the custom property.
    const ratio = scrollable > 0 ? window.scrollY / scrollable : 0;
    progress.style.setProperty("--reading-progress", Math.min(1, Math.max(0, ratio)).toFixed(4));
  };

  const onScroll = () => {
    nav?.classList.toggle("is-scrolled", window.scrollY > 12);
    if (!cssDrivesProgress) setProgress();
  };
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });
  // Rotating a phone or opening the keyboard changes the scrollable height, so
  // the same fraction of the page is a different transform afterwards.
  window.addEventListener("resize", onScroll, { passive: true });

  const setMenu = (open) => {
    toggle?.classList.toggle("is-open", open);
    overlay?.classList.toggle("is-open", open);
    toggle?.setAttribute("aria-expanded", String(open));
    document.body.style.overflow = open ? "hidden" : "";
  };

  toggle?.addEventListener("click", () => {
    setMenu(!toggle.classList.contains("is-open"));
  });

  overlay?.querySelectorAll("a").forEach((link) => {
    link.addEventListener("click", () => setMenu(false));
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      setMenu(false);
      closeLightbox();
    }
  });

  if (!reduce && "IntersectionObserver" in window) {
    const io = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-in");
            io.unobserve(entry.target);
          }
        }
      },
      { threshold: 0.12, rootMargin: "0px 0px -8% 0px" }
    );
    document.querySelectorAll(".reveal").forEach((el, i) => {
      el.style.transitionDelay = `${Math.min(i % 6, 5) * 70}ms`;
      io.observe(el);
    });
  } else {
    document.querySelectorAll(".reveal").forEach((el) => el.classList.add("is-in"));
  }

  const openLightbox = (src, alt) => {
    if (!lightbox || !lightboxImg) return;
    lightboxImg.src = src;
    lightboxImg.alt = alt || "";
    lightbox.classList.add("is-open");
    lightbox.setAttribute("aria-hidden", "false");
    document.body.style.overflow = "hidden";
  };

  const closeLightbox = () => {
    lightbox?.classList.remove("is-open");
    lightbox?.setAttribute("aria-hidden", "true");
    if (!overlay?.classList.contains("is-open")) {
      document.body.style.overflow = "";
    }
  };

  document.querySelectorAll("[data-zoom]").forEach((el) => {
    el.addEventListener("click", () => {
      const img = el.querySelector("img") || el;
      openLightbox(img.currentSrc || img.src, img.alt);
    });
  });

  lightbox?.addEventListener("click", (event) => {
    if (event.target === lightbox || event.target.closest("button")) closeLightbox();
  });

  document.querySelectorAll("[data-copy]").forEach((button) => {
    button.addEventListener("click", async () => {
      const text = document.querySelector(button.getAttribute("data-copy"))?.innerText;
      if (!text) return;
      try {
        await navigator.clipboard.writeText(text.trim());
        const previous = button.textContent;
        button.textContent = "Copied";
        setTimeout(() => {
          button.textContent = previous;
        }, 1600);
      } catch {
        button.textContent = "Select & copy";
      }
    });
  });

  const navLinks = [...document.querySelectorAll(".nav-links a, .overlay a[href^='#']")];
  const sectionIds = [...new Set(navLinks.map((link) => link.getAttribute("href")?.slice(1)).filter(Boolean))];

  const setActive = (id) => {
    navLinks.forEach((link) => {
      const on = link.getAttribute("href") === `#${id}`;
      link.classList.toggle("is-active", on);
      if (on) link.setAttribute("aria-current", "location");
      else link.removeAttribute("aria-current");
    });
  };

  const spy = () => {
    const line = 128;
    let current = "";
    for (const id of sectionIds) {
      const el = document.getElementById(id);
      if (!el) continue;
      if (el.getBoundingClientRect().top <= line) current = id;
    }
    const atBottom =
      window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 48;
    if (atBottom) current = sectionIds.at(-1) || current;
    setActive(current);
  };

  spy();
  window.addEventListener("scroll", spy, { passive: true });
  window.addEventListener("resize", spy);
})();
