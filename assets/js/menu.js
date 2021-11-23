const burgerButton = document.querySelector(".header__nav__btn");
const navLinks = document.querySelector(".header__nav__links");

burgerButton.addEventListener("click", function () {

  burgerButton.classList.toggle("responsive");
  navLinks.classList.toggle("responsive");
});
