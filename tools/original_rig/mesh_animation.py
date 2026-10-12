"""Bounded low-rank compression of evaluated Skin positions.

The error gate measures every vertex, rather than discarding components by
their global energy. Temporal coefficients remain signed and are exported as
linear morph weights. No Skin influences are selected or truncated here.
"""
import numpy as np


def compress_frames(frames, max_error=.00015):
    frames = np.asarray(frames, dtype=np.float32)
    if frames.ndim != 3 or frames.shape[-1] != 3 or not np.isfinite(frames).all():
        raise ValueError('Expected finite frame × vertex × XYZ positions')
    if max_error <= 0:
        raise ValueError('Maximum vertex error must be positive')
    delta = (frames-frames[0]).reshape(len(frames), -1)
    if not np.any(delta):
        return np.zeros((0, *frames.shape[1:]), np.float32), np.zeros((len(frames), 0), np.float32), 0.
    # The temporal Gram matrix is small (181 × 181), unlike a spatial SVD of
    # the complete body. Double precision prevents tiny eigenmodes becoming
    # numerically negative when large trunk translation dominates the action.
    gram = delta.astype(np.float64) @ delta.astype(np.float64).T
    values, vectors = np.linalg.eigh(gram)
    order = np.argsort(values)[::-1]
    vectors = vectors[:, order].astype(np.float32)
    spatial = vectors.T @ delta
    decoded = np.zeros_like(delta)
    error = float('inf')
    rank = 0
    for rank in range(1, len(frames)+1):
        decoded += vectors[:, rank-1:rank] @ spatial[rank-1:rank]
        error = float(np.linalg.norm((decoded-delta).reshape(frames.shape), axis=2).max())
        if error <= max_error:
            break
    if error > max_error:
        raise RuntimeError('Full mesh animation exceeds the requested numeric error bound')
    # Keep target positions within the scale of each actual motion component;
    # weights normalize to [-1, 1], which model-viewer supports for morphs.
    scale = np.max(np.abs(vectors[:, :rank]), axis=0)
    targets = (spatial[:rank]*scale[:, None]).reshape(rank, *frames.shape[1:])
    weights = vectors[:, :rank]/scale
    weights[0] = 0
    return targets.astype(np.float32), weights.astype(np.float32), error


def unsigned_components(targets, weights):
    """Use only [0, 1] weights, including importers that clamp signed keys."""
    exported = []; coefficients = []
    for target, values in zip(targets, weights.T):
        if np.any(values > 0):
            exported.append(target); coefficients.append(np.maximum(values, 0))
        if np.any(values < 0):
            exported.append(-target); coefficients.append(np.maximum(-values, 0))
    if not exported:
        return targets[:0], weights[:, :0]
    return np.asarray(exported, dtype=np.float32), np.asarray(coefficients, dtype=np.float32).T
