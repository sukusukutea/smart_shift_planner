// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import "./controllers"
import "bootstrap"

document.addEventListener("change", (e) => {
  const t = e.target;
  if (!t) return;

  // workday_constraint のラジオだけ反応させる
  if (t.name !== "staff[workday_constraint]") return;

  const fieldset = document.getElementById("workable-wdays-fieldset");
  if (!fieldset) return;

  const fixed = (t.value === "fixed");

  fieldset.disabled = !fixed;
  fieldset.classList.toggle("is-enabled", fixed);
  fieldset.classList.toggle("is-disabled", !fixed);
});
