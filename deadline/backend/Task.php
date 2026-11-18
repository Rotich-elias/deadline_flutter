<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Task extends Model
{
    protected $keyType = 'string';
    public $incrementing = false;

    /**
     * Timestamps come from the device, not from the server clock, so Eloquent
     * must not touch updated_at on save.
     */
    public $timestamps = false;

    protected $fillable = [
        'id', 'user_id', 'title', 'notes', 'tag',
        'due_at', 'done', 'deleted', 'repeat', 'pinned', 'priority',
        'checklist', 'assigned_to', 'comments',
        'category', 'start_at', 'labels', 'location_alert',
        'updated_at', 'created_at', 'synced_at',
    ];

    protected $casts = [
        'due_at' => 'datetime',
        'updated_at' => 'datetime',
        'created_at' => 'datetime',
        'synced_at' => 'datetime',
        'done' => 'boolean',
        'deleted' => 'boolean',
        'repeat' => 'integer',
        'pinned' => 'boolean',
        'priority' => 'integer',
        'checklist' => 'array',
        'comments' => 'array',
        'start_at' => 'datetime',
        'labels' => 'array',
        'location_alert' => 'array',
    ];

    public function toSyncArray(): array
    {
        return [
            'id' => $this->id,
            'title' => $this->title,
            'notes' => $this->notes,
            'tag' => $this->tag,
            'due_at' => $this->due_at->toIso8601String(),
            'done' => $this->done,
            'deleted' => $this->deleted,
            'repeat' => $this->repeat,
            'pinned' => $this->pinned,
            'priority' => $this->priority,
            'checklist' => $this->checklist ?? [],
            'assigned_to' => $this->assigned_to,
            'comments' => $this->comments ?? [],
            'category' => $this->category,
            'start_at' => $this->start_at?->toIso8601String(),
            'labels' => $this->labels ?? [],
            'location_alert' => $this->location_alert ?? [],
            'updated_at' => $this->updated_at->toIso8601String(),
        ];
    }
}
