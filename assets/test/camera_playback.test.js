// SPDX-FileCopyrightText: 2026 James Harton
//
// SPDX-License-Identifier: Apache-2.0

import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  describePlayback,
  framesPerSecond,
  iceServersFrom,
  lowerLatency,
  tagSignal,
} from "../js/camera/playback.js";

function element(dataset) {
  return { dataset };
}

describe("iceServersFrom", () => {
  test("reads the servers the dashboard was configured with", () => {
    const servers = [{ urls: "turn:turn.example.com:3478", username: "robot", credential: "secret" }];

    assert.deepEqual(iceServersFrom(element({ iceServers: JSON.stringify(servers) })), servers);
  });

  test("uses none when there are none", () => {
    assert.deepEqual(iceServersFrom(element({})), []);
    assert.deepEqual(iceServersFrom(element({ iceServers: "[]" })), []);
  });

  test("uses none rather than failing on something that isn't a list", () => {
    assert.deepEqual(iceServersFrom(element({ iceServers: "not json" })), []);
    assert.deepEqual(iceServersFrom(element({ iceServers: "{}" })), []);
  });
});

describe("tagSignal", () => {
  test("names the camera and session a message belongs to", () => {
    const answer = { type: "sdp_answer", data: { type: "answer", sdp: "v=0" } };

    assert.deepEqual(tagSignal(answer, element({ camera: "eye", session: "3" })), {
      ...answer,
      camera: "eye",
      session: 3,
    });
  });
});

describe("lowerLatency", () => {
  test("asks for the smallest jitter buffer the browser offers", () => {
    const receiver = { jitterBufferTarget: 150, playoutDelayHint: 0.5 };

    lowerLatency(receiver);

    assert.equal(receiver.jitterBufferTarget, 0);
    assert.equal(receiver.playoutDelayHint, 0);
  });

  test("leaves alone knobs the browser doesn't have", () => {
    const receiver = {};

    lowerLatency(receiver);

    assert.deepEqual(receiver, {});
  });
});

describe("framesPerSecond", () => {
  test("is the frames shown between two samples, per second", () => {
    assert.equal(framesPerSecond({ frames: 10, time: 1000 }, { frames: 40, time: 2000 }), 30);
  });

  test("has nothing to say from a single sample", () => {
    assert.equal(framesPerSecond(null, { frames: 40, time: 2000 }), null);
  });

  test("starts again when a new stream resets the counter", () => {
    assert.equal(framesPerSecond({ frames: 400, time: 1000 }, { frames: 3, time: 2000 }), null);
  });
});

describe("describePlayback", () => {
  test("shows the frame rate once connected", () => {
    assert.equal(describePlayback("connected", 29.97), "connected · 30.0 fps");
  });

  test("shows only the state until then", () => {
    assert.equal(describePlayback("connecting", null), "connecting");
    assert.equal(describePlayback("failed", 12), "failed");
  });
});
