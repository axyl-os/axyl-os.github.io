const burgerButton = document.querySelector(".header__nav__btn");
const navLinks = document.querySelector(".header__nav__links");

burgerButton.addEventListener("click", function () {
  if (!this.classList.contains("responsive")) {
    this.classList.add("responsive");

    if (!navLinks.classList.contains("disappear")) {
      navLinks.classList.add("appear");
    }

  } else {
    this.classList.remove("responsive");
    navLinks.classList.remove("responsive");

    if (!navLinks.classList.contains("appear")) {
      navLinks.classList.add("disappear");
    }
    
  }
});

navLinks.addEventListener("animationend", (e) => {
  if (e.target.classList.contains("appear")) {
    e.target.classList.add("responsive");
    e.target.classList.remove("appear");
  } else if (e.target.classList.contains("disappear")) {
    e.target.classList.remove("disappear");
  }
});
