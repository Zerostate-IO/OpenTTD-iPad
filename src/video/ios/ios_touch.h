/**
 * @file ios_touch.h
 * @brief iOS touch gesture recognizer for OpenTTD.
 */

#ifndef IOS_TOUCH_H
#define IOS_TOUCH_H

#ifdef __APPLE__
#include <TargetConditionals.h>
#endif

#if TARGET_OS_IOS

#include "../../core/geometry_type.hpp"
#include <chrono>
#include <map>

/**
 * State of the gesture recognizer.
 */
enum class GestureState {
	IDLE,
	TAP_PENDING,          ///< Waiting to see if it's a tap or drag
	DRAGGING,             ///< Single finger drag (pan)
	LONG_PRESS_PENDING,   ///< Waiting for long-press threshold
	TWO_FINGER_PAN,       ///< Two finger drag
	PINCH_ZOOM,           ///< Pinch gesture active
};

/**
 * Information about a single active touch.
 */
struct TouchPoint {
	int touch_id;
	Point position;
	Point start_position;
	std::chrono::steady_clock::time_point start_time;
	bool is_active;
};

/**
 * Handles raw touch events and translates them into OpenTTD-friendly gestures.
 * Implements a state machine to detect taps, drags, pinches, etc.
 */
class TouchGestureRecognizer {
public:
	// Constants per Phase 2 spec
	static constexpr int LONG_PRESS_THRESHOLD_MS = 500;
	static constexpr int TAP_MOVEMENT_THRESHOLD = 15;  // pixels
	static constexpr int DOUBLE_TAP_INTERVAL_MS = 300;
	static constexpr float PINCH_ZOOM_IN_THRESHOLD = 1.5f;
	static constexpr float PINCH_ZOOM_OUT_THRESHOLD = 0.67f;

	TouchGestureRecognizer();

	void TouchBegan(int touch_id, float x, float y);
	void TouchMoved(int touch_id, float x, float y);
	void TouchEnded(int touch_id, float x, float y);
	void Update();  ///< Called each frame for time-based gestures

	// Query output state
	bool HasPendingClick() const;
	bool HasPendingRightClick() const;
	Point GetClickPosition() const;

	bool IsDragging() const;
	Point GetDragDelta() const;

	bool IsPinching() const;
	float GetPinchScale() const;
	Point GetPinchCenter() const;

	void ClearPendingEvents();

private:
	GestureState state;
	std::map<int, TouchPoint> active_touches;

	// Output state
	bool pending_click;
	bool pending_right_click;
	Point click_position;
	Point drag_delta;
	float pinch_scale;
	Point pinch_center;
	float initial_pinch_distance;

	// For double-tap detection
	std::chrono::steady_clock::time_point last_tap_time;
	Point last_tap_position;

	void TransitionState(GestureState new_state);
	float GetDistanceBetweenTouches() const;
	Point GetMidpointBetweenTouches() const;
};

#endif /* TARGET_OS_IOS */
#endif /* IOS_TOUCH_H */
