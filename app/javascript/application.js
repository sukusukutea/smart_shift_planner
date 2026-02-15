// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import "./controllers"
import "bootstrap"

document.addEventListener("change", (e) => {
  const t = e.target;
  if (!t) return;

  // workday_constraint のラジオだけ反応させる
  if (t.name !== "staff[workday_constraint]") return;

  const workable = document.getElementById("workable-wdays-fieldset");
  const unworkable = document.getElementById("unworkable-wdays-fieldset");
  if (!workable && !unworkable) return;

  const fixed = (t.value === "fixed");
  const free  = !fixed;

  if (workable) {
    workable.disabled = !fixed;
    workable.classList.toggle("is-enabled", fixed);
    workable.classList.toggle("is-disabled", !fixed);
  }

  if (unworkable) {
    unworkable.disabled = !free;
    unworkable.classList.toggle("is-enabled", free);
    unworkable.classList.toggle("is-disabled", !free);
  }
});
