// SPDX-FileCopyrightText: 2026 James Harton
//
// SPDX-License-Identifier: Apache-2.0

import assert from "node:assert/strict";
import { test } from "node:test";

import {
  BLANK_IMAGE,
  CameraPreview,
  stopStreaming,
} from "../js/hooks/camera_preview.js";

// The smallest thing that behaves like an <img> for this purpose. Assigning
// `src` is what cancels a request in flight, so every assignment is recorded;
// `removeAttribute` only notes that it was called, because what matters is
// what the hook did, not what a real DOM would do in response.
function trackingImage(src) {
  const assigned = [];
  const removed = [];
  let current = src;

  return {
    assigned,
    removed,

    get src() {
      return current;
    },

    set src(value) {
      assigned.push(value);
      current = value;
    },

    removeAttribute(name) {
      removed.push(name);
    },
  };
}

test("cancels the stream by assigning a new source", () => {
  const image = trackingImage("/robot/__bb_camera__/eye/mjpeg?g=0");

  stopStreaming(image);

  assert.equal(image.assigned[0], BLANK_IMAGE);
});

test("never assigns an empty source, which refetches the page itself", () => {
  const image = trackingImage("/robot/__bb_camera__/eye/mjpeg?g=0");

  stopStreaming(image);

  for (const value of image.assigned) {
    assert.notEqual(value, "");
    assert.ok(value.startsWith("data:"), `${value} is not a data URL`);
  }
});

test("removes the attribute once the request is cancelled", () => {
  const image = trackingImage("/robot/__bb_camera__/eye/mjpeg?g=0");

  stopStreaming(image);

  assert.deepEqual(image.removed, ["src"]);
});

test("cancels before the element is thrown away", () => {
  const image = trackingImage("/robot/__bb_camera__/eye/mjpeg?g=0");

  CameraPreview.destroyed.call({ el: image });

  assert.equal(image.assigned[0], BLANK_IMAGE);
});

test("cancels before a resumed preview replaces the URL", () => {
  const image = trackingImage("/robot/__bb_camera__/eye/mjpeg?g=0");

  CameraPreview.beforeUpdate.call({ el: image });

  assert.equal(image.assigned[0], BLANK_IMAGE);
});

test("says nothing about an element that is already gone", () => {
  assert.doesNotThrow(() => stopStreaming(null));
  assert.doesNotThrow(() => stopStreaming(undefined));
});
