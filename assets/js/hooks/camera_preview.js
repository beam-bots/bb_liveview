// SPDX-FileCopyrightText: 2026 James Harton
//
// SPDX-License-Identifier: Apache-2.0

/**
 * LiveView hook that stops an MJPEG preview when it leaves the page.
 *
 * Removing an <img> from the DOM does not reliably abort a request that is
 * still streaming: a multipart/x-mixed-replace response never ends on its own,
 * and Chrome and Firefox both keep reading it after the element is detached.
 * The connection stays open, so the camera keeps a consumer and keeps
 * capturing — the webcam light stays on after Pause.
 *
 * Assigning a new src is what actually cancels the load in flight. A data URL
 * is used rather than an empty string, because an empty src re-resolves to the
 * page's own URL and fetches the dashboard into the image.
 *
 * This only ever stops *this* viewer's request. Whether the camera then stops
 * capturing is the hub's decision, made on its own subscriber count, so a
 * second browser watching the same camera is unaffected.
 */

// A 1x1 transparent GIF: the smallest thing that is a valid image and makes no
// request.
export const BLANK_IMAGE =
  "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7";

export function stopStreaming(image) {
  if (!image) {
    return;
  }

  // Order matters. The assignment cancels the request that is in flight;
  // removing the attribute afterwards stops the blank frame being refetched
  // if the element is ever reattached.
  image.src = BLANK_IMAGE;
  image.removeAttribute("src");
}

export const CameraPreview = {
  destroyed() {
    stopStreaming(this.el);
  },

  beforeUpdate() {
    // A resumed preview gets a new URL on the same element. Cancelling first
    // means the old stream is released even where the browser would otherwise
    // hold both open while the new one connects.
    stopStreaming(this.el);
  },
};
