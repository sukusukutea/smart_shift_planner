// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import "./controllers"
import "bootstrap"

function updateWorkdayConstraintUI(value) {
  const workable    = document.getElementById("workable-wdays-fieldset");
  const unworkable  = document.getElementById("unworkable-wdays-fieldset");
  const weeklyField = document.getElementById("weekly-workdays-field");

  const isFixed  = (value === "fixed");
  const isFree   = (value === "free");
  const isWeekly = (value === "weekly");

  if (workable) {
    workable.disabled = !isFixed;
    workable.classList.toggle("is-enabled", isFixed);
    workable.classList.toggle("is-disabled", !isFixed);
  }

  const enableUnworkable = isFree;

  if (unworkable) {
    unworkable.disabled = !enableUnworkable;
    unworkable.classList.toggle("is-enabled", enableUnworkable);
    unworkable.classList.toggle("is-disabled", !enableUnworkable);
  }

  if (weeklyField) {
    weeklyField.classList.toggle("is-enabled", isWeekly);
    weeklyField.classList.toggle("is-disabled", !isWeekly);

    const input = weeklyField.querySelector("input");
    if (input) input.disabled = !isWeekly;
  }

  const weeklyUnworkable = document.getElementById("weekly-unworkable-wdays");

  if (weeklyUnworkable) {
    weeklyUnworkable.classList.toggle("is-enabled", isWeekly);
    weeklyUnworkable.classList.toggle("is-disabled", !isWeekly);

    weeklyUnworkable.querySelectorAll('input[type="checkbox"]').forEach((cb) => {
      cb.disabled = !isWeekly;
    });
  }

  const freeGroup   = document.getElementById("free-group");
  const fixedGroup  = document.getElementById("fixed-group");
  const weeklyGroup = document.getElementById("weekly-group");

  if (freeGroup)  freeGroup.classList.toggle("is-disabled", isFixed || isWeekly);
  if (fixedGroup) fixedGroup.classList.toggle("is-disabled", isFree  || isWeekly);
  if (weeklyGroup) weeklyGroup.classList.toggle("is-disabled", isFree || isFixed);
}

document.addEventListener("turbo:load", () => {
  const checked = document.querySelector('input[name="staff[workday_constraint]"]:checked');
  if (checked) updateWorkdayConstraintUI(checked.value);
});

document.addEventListener("change", (e) => {
  const t = e.target;
  if (!t) return;
  if (t.name !== "staff[workday_constraint]") return;

  updateWorkdayConstraintUI(t.value);
});