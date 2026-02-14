/**
 * Mobile dropdown toggle for secondary menu/widgets.
 * Toggles the "Menu and widgets" panel on small screens.
 */
(function () {
  var toggle = document.querySelector('.secondary-toggle');
  var secondary = document.getElementById('secondary');

  if (!toggle || !secondary) return;

  toggle.addEventListener('click', function () {
    var isExpanded = toggle.classList.toggle('toggled-on');
    secondary.classList.toggle('toggled-on', isExpanded);
    toggle.setAttribute('aria-expanded', isExpanded);
  });
})();
