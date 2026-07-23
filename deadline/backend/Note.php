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
        'deleted', 'updated_at', 'created_at',
    ];

    protected $casts = [
        'updated_at' => 'datetime',
        'created_at' => 'datetime',
        'deleted' => 'boolean',
    ];

    public function toSyncArray(): array
    {
        return [
            'id' => $this->id,
            'title' => $this->title,
            'body' => $this->body,
            'tag' => $this->tag,
            'deleted' => $this->deleted,
            'updated_at' => $this->updated_at->toIso8601String(),
        ];
    }
}
