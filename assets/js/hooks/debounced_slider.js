// SPDX-FileCopyrightText: 2025 James Harton
// SPDX-License-Identifier: Apache-2.0

export const DebouncedSlider = {
  mounted() {
    this.debounceTimeout = null;
    this.debounceMs = parseInt(this.el.dataset.debounce || "100");

    this.el.addEventListener("input", (e) => {
      clearTimeout(this.debounceTimeout);
      this.debounceTimeout = setTimeout(() => {
        this.pushEvent("slider_change", {
          name: this.el.dataset.name,
          value: parseFloat(e.target.value),
        });
      }, this.debounceMs);
    });
  },

  destroyed() {
    clearTimeout(this.debounceTimeout);
  },
};
