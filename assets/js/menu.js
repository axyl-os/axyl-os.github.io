const burgerButton = document.querySelector(".header__nav__btn");
const navLinks = document.querySelector(".header__nav__links");

burgerButton.addEventListener("click", function () {
  if (!this.classList.contains("responsive")) {
    this.classList.add("responsive");

    navLinks.classList.add("responsive");

    navLinks.classList.add("appear");
    navLinks.classList.remove("disappear");

  } else {
    this.classList.remove("responsive");

    navLinks.classList.remove("responsive");

    navLinks.classList.remove("appear");
    navLinks.classList.add("disappear");
  }
});

navLinks.addEventListener("animationend", (e) => {
  if (e.target.classList.contains("appear")) {
    e.target.classList.remove("appear");
  } else if (e.target.classList.contains("disappear")) {
    e.target.classList.remove("disappear");
  }
});
