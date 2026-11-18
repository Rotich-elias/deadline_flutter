<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Copy to app/Models/SharedList.php in the Laravel application.
 *
 * A shared list belongs to one account but can also be reached by everybody
 * whose invitation has been accepted. The tasks pivot uses the client-side
 * UUID primary key from the tasks table.
 */
class SharedList extends Model
{
    protected $fillable = [
        'user_id', 'name', 'owner_email',
    ];

    public function owner()
    {
        return $this->belongsTo(User::class, 'user_id');
    }

    public function invitations()
    {
        return $this->hasMany(Invitation::class);
    }

    public function tasks()
    {
        return $this->belongsToMany(Task::class, 'shared_list_task', 'shared_list_id', 'task_id');
    }
}
