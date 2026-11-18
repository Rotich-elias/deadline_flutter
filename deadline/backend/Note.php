<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Note extends Model
{
    protected $keyType = 'string';
    public $incrementing = false;

    /**
     * Timestamps come from the device, not from the server clock, so Eloquent
     * must not touch updated_at on save.
     */
    public $timestamps = false;

    protected $fillable = [
        'id', 'user_id', 'title', 'body', 'tag',
        'deleted', 'pinned', 'attachments', 'notebook', 'labels',
        'updated_at', 'created_at', 'synced_at',
    ];

    protected $casts = [
        'updated_at' => 'datetime',
        'created_at' => 'datetime',
        'synced_at' => 'datetime',
        'deleted' => 'boolean',
        'pinned' => 'boolean',
        'attachments' => 'array',
        'labels' => 'array',
    ];

    public function toSyncArray(): array
    {
        return [
            'id' => $this->id,
            'title' => $this->title,
            'body' => $this->body,
            'tag' => $this->tag,
            'deleted' => $this->deleted,
            'pinned' => $this->pinned,
            'attachments' => $this->attachments ?? [],
            'notebook' => $this->notebook,
            'labels' => $this->labels ?? [],
            'updated_at' => $this->updated_at->toIso8601String(),
        ];
    }
}
