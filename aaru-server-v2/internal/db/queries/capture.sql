-- Capture inputs (AG-006): written with the job, gone once read (PostgresCaptureStore).

-- name: CaptureInputSave :exec
INSERT INTO capture_inputs (job_id, user_id, kind, text, image, media_type, only_type, created_at)
VALUES (@job_id, @user_id, @kind, sqlc.narg('text'), sqlc.narg('image'), sqlc.narg('media_type'), sqlc.narg('only_type'), @created_at);

-- name: CaptureImageSave :exec
INSERT INTO capture_images (job_id, position, image, media_type) VALUES (@job_id, @position, @image, @media_type);

-- name: CaptureImages :many
SELECT image, media_type FROM capture_images WHERE job_id = @job_id ORDER BY position;

-- name: CaptureInputGet :many
SELECT user_id, text, image, media_type, only_type, created_at FROM capture_inputs WHERE job_id = @job_id;

-- name: CaptureInputDelete :exec
DELETE FROM capture_inputs WHERE job_id = @job_id;

-- name: CaptureInputSweep :many
DELETE FROM capture_inputs WHERE created_at < @before RETURNING job_id;
