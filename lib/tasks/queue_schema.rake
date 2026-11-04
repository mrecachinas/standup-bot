# Development's queue database is loaded from Solid Queue's stock
# db/queue_schema.rb, which production loads into PostgreSQL too. db:migrate
# dumps every database afterwards, which would rewrite that file as a MySQL
# dump, so skip the dump for the development queue database. Loading the
# schema (db:prepare, db:schema:load) is unaffected.
module KeepStockQueueSchema
  def dump_schema(db_config, *)
    return if db_config.env_name == "development" && db_config.name == "queue"

    super
  end
end

ActiveRecord::Tasks::DatabaseTasks.singleton_class.prepend(KeepStockQueueSchema)
