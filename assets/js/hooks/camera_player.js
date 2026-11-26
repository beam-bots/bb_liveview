// SPDX-FileCopyrightText: 2026 James Harton
//
// SPDX-License-Identifier: Apache-2.0

/**
 * LiveView hook that plays a camera preview: `bb_camera_webrtc`'s player,
 * plus what a dashboard needs around it.
 *
 * The player owns the peer connection — it answers the server's offer and
 * trades ICE candidates over `webrtc_signaling` events. Around it, this hook
 *
 *   - tags every message with the camera and session it belongs to;
 *   - takes its ICE servers from the element, so they can be configured on
 *     the server rather than baked into this bundle;
 *   - asks the browser for its smallest jitter buffer; and
 *   - shows the connection state and the frame rate actually played.
 *
 * A stream that ends is replaced by the server with a new session, which is a
 * new element id: LiveView destroys this hook, closing its connection, and
 * mounts a fresh one. Nothing here reconnects by itself.
 */

import { createPlayerHook } from "bb_camera_webrtc/assets/player.js";

import {
  describePlayback,
  framesPerSecond,
  iceServersFrom,
  lowerLatency,
  tagSignal,
} from "../camera/playback.js";

export const CameraPlayer = {
  mounted() {
    // Autoplay without a user gesture needs the property, and the attribute
    // alone doesn't set it on an element inserted by a DOM patch.
    this.el.muted = true;

    const pushEventTo = this.pushEventTo.bind(this);
    this.pushEventTo = (target, event, payload) =>
      pushEventTo(target, event, event === "webrtc_signaling" ? tagSignal(payload, this.el) : payload);

    this.player = createPlayerHook(iceServersFrom(this.el));
    this.player.mounted.call(this);

    this.pc.addEventListener("track", ({ receiver }) => lowerLatency(receiver));
    this.pc.addEventListener("connectionstatechange", () => this.showPlayback());

    this.playback = document.getElementById(`${this.el.id}-playback`);
    this.startMeter();
    this.showPlayback();
  },

  destroyed() {
    clearInterval(this.meter);
    if (this.frameCallback != null) this.el.cancelVideoFrameCallback(this.frameCallback);
    this.player.destroyed.call(this);
  },

  // Frames presented, from requestVideoFrameCallback where the browser has
  // it, otherwise from the playback quality counters.
  startMeter() {
    this.presented = null;
    this.fps = null;
    let previous = null;

    if ("requestVideoFrameCallback" in this.el) {
      const onFrame = (_now, metadata) => {
        this.presented = metadata.presentedFrames;
        this.frameCallback = this.el.requestVideoFrameCallback(onFrame);
      };
      this.frameCallback = this.el.requestVideoFrameCallback(onFrame);
    }

    this.meter = setInterval(() => {
      const frames = this.presented ?? this.el.getVideoPlaybackQuality?.().totalVideoFrames;
      if (frames == null) return;

      const current = { frames, time: performance.now() };
      this.fps = framesPerSecond(previous, current);
      previous = current;
      this.showPlayback();
    }, 1000);
  },

  showPlayback() {
    if (this.playback) this.playback.textContent = describePlayback(this.pc.connectionState, this.fps);
  },
};
