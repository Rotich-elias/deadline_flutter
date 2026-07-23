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
        'due_at', 'done', 'deleted', 'repeat', 'updated_at', 'created_at',
    ];

    protected $casts = [
        'due_at' => 'datetime',
        'updated_at' => 'datetime',
        'created_at' => 'datetime',
        'done' => 'boolean',
        'deleted' => 'boolean',
        'repeat' => 'integer',
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
            'updated_at' => $this->updated_at->toIso8601String(),
        ];
    }
}
