-- Capture inputs (AG-006): written with the job, gone once read (PostgresCaptureStore).

-- name: CaptureInputSave :exec
INSERT INTO capture_inputs (job_id, user_id, kind, text, image, media_type, created_at)
VALUES (@job_id, @user_id, @kind, sqlc.narg('text'), sqlc.narg('image'), sqlc.narg('media_type'), @created_at);

-- name: CaptureInputGet :many
SELECT user_id, text, image, media_type, created_at FROM capture_inputs WHERE job_id = @job_id;

-- name: CaptureInputDelete :exec
DELETE FROM capture_inputs WHERE job_id = @job_id;

-- name: CaptureInputSweep :many
DELETE FROM capture_inputs WHERE created_at < @before RETURNING job_id;
