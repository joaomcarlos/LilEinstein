/* ============================================
   LilEinstein — Landing Page Interactions
   ============================================ */

(function () {
  'use strict';

  // Nav scroll effect
  const nav = document.getElementById('nav');
  let lastScroll = 0;

  function handleScroll() {
    const scroll = window.scrollY;
    if (scroll > 20) {
      nav.classList.add('scrolled');
    } else {
      nav.classList.remove('scrolled');
    }
    lastScroll = scroll;
  }

  window.addEventListener('scroll', handleScroll, { passive: true });

  // Mobile nav toggle
  const navToggle = document.getElementById('navToggle');
  const navLinks = document.querySelector('.nav-links');

  if (navToggle) {
    navToggle.addEventListener('click', function () {
      navLinks.classList.toggle('open');
    });

    navLinks.querySelectorAll('a').forEach(function (link) {
      link.addEventListener('click', function () {
        navLinks.classList.remove('open');
      });
    });
  }

  // Scroll reveal animation
  const revealElements = document.querySelectorAll(
    '.feature-card, .strategy-card, .install-card, .showcase-item, .changelog-entry, .compat-notice, .section-header'
  );

  revealElements.forEach(function (el) {
    el.classList.add('reveal');
  });

  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            entry.target.classList.add('visible');
            observer.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.1, rootMargin: '0px 0px -40px 0px' }
    );

    revealElements.forEach(function (el) {
      observer.observe(el);
    });
  } else {
    revealElements.forEach(function (el) {
      el.classList.add('visible');
    });
  }

  // Smooth scroll for anchor links
  document.querySelectorAll('a[href^="#"]').forEach(function (anchor) {
    anchor.addEventListener('click', function (e) {
      const target = document.querySelector(this.getAttribute('href'));
      if (target) {
        e.preventDefault();
        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
    });
  });

  // Active nav link tracking
  const sections = document.querySelectorAll('section[id], header[id]');
  const navItems = document.querySelectorAll('.nav-links a');

  function trackActiveSection() {
    const scrollPos = window.scrollY + 100;
    sections.forEach(function (section) {
      const top = section.offsetTop;
      const height = section.offsetHeight;
      const id = section.getAttribute('id');
      if (scrollPos >= top && scrollPos < top + height) {
        navItems.forEach(function (item) {
          if (item.getAttribute('href') === '#' + id) {
            item.style.color = 'var(--text)';
          } else {
            item.style.color = '';
          }
        });
      }
    });
  }

  window.addEventListener('scroll', trackActiveSection, { passive: true });
})();
