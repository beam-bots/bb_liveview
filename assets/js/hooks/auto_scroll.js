// SPDX-FileCopyrightText: 2025 James Harton
// SPDX-License-Identifier: Apache-2.0

export const AutoScroll = {
  mounted() {
    this.scrollToBottom();
  },

  updated() {
    if (this.el.dataset.paused !== "true") {
      this.scrollToBottom();
    }
  },

  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight;
  },
};
