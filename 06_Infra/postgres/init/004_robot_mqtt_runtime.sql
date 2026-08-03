BEGIN;

ALTER TABLE robot_current_states
    ADD COLUMN IF NOT EXISTS last_message_id UUID;

CREATE UNIQUE INDEX IF NOT EXISTS uq_robot_current_states_last_message
    ON robot_current_states (last_message_id)
    WHERE last_message_id IS NOT NULL;

ALTER TABLE behavior_requests
    ADD COLUMN IF NOT EXISTS last_result_message_id UUID;

CREATE UNIQUE INDEX IF NOT EXISTS uq_behavior_requests_last_result_message
    ON behavior_requests (last_result_message_id)
    WHERE last_result_message_id IS NOT NULL;

COMMIT;
