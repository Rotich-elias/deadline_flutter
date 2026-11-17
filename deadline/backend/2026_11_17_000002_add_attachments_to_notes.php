<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Attachment metadata (name, MIME type, size, id) travels with the note as a
 * JSON array. The file bytes stay in the device's app storage; the sync row
 * only lets another device show "not downloaded" where appropriate.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('notes', function (Blueprint $table) {
            $table->json('attachments')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('notes', function (Blueprint $table) {
            $table->dropColumn('attachments');
        });
    }
};
