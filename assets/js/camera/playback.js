// SPDX-FileCopyrightText: 2026 James Harton
//
// SPDX-License-Identifier: Apache-2.0

/**
 * The parts of a camera preview that don't need a browser: what the server
 * told the <video> element, what the hook tells the server, and what the
 * viewer is shown about the stream.
 */

export function iceServersFrom(element) {
  try {
    const servers = JSON.parse(element.dataset.iceServers || "[]");
    return Array.isArray(servers) ? servers : [];
  } catch {
    return [];
  }
}

// Several previews share one component, and a camera that is watched again
// gets a new session: the server needs both to know which stream a reply
// belongs to, and to drop one from a stream that has already ended.
export function tagSignal(payload, element) {
  return {
    ...payload,
    camera: element.dataset.camera,
    session: Number(element.dataset.session),
  };
}

// Play each frame as soon as it can be decoded rather than buffering for
// smoothness: this is a robot being driven, not a film. `jitterBufferTarget`
// is the standard knob, in milliseconds; `playoutDelayHint` is Chrome's older
// one, in seconds.
export function lowerLatency(receiver) {
  if ("jitterBufferTarget" in receiver) receiver.jitterBufferTarget = 0;
  if ("playoutDelayHint" in receiver) receiver.playoutDelayHint = 0;
}

// Frames actually shown per second between two samples of the element's
// presented-frame counter. A new stream starts counting from zero again, so a
// counter that went backwards has no rate yet.
export function framesPerSecond(previous, current) {
  if (previous === null || current.frames < previous.frames) return null;
  const seconds = (current.time - previous.time) / 1000;
  if (seconds <= 0) return null;
  return (current.frames - previous.frames) / seconds;
}

export function describePlayback(connectionState, fps) {
  if (connectionState !== "connected" || fps === null) return connectionState;
  return `${connectionState} · ${fps.toFixed(1)} fps`;
}
