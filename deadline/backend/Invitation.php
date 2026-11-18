<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Copy to app/Models/Invitation.php in the Laravel application.
 *
 * The random token is the only secret handed to an invitee; acceptance also
 * checks that the signed-in account's email matches the invited address.
 */
class Invitation extends Model
{
    protected $fillable = [
        'shared_list_id', 'email', 'role', 'token', 'status',
    ];

    public function list()
    {
        return $this->belongsTo(SharedList::class, 'shared_list_id');
    }
}
