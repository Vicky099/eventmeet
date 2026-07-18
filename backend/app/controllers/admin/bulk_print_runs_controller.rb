module Admin
  # Phase 10 revisit — Bulk Print (requirement.md §3.6/§5.5's baseline "bulk print queue"). Only
  # :new/:create/:show — a run is requested once (station + batch limit) and then only ever
  # watched, same "no :edit/:update" shape :quotations already takes for a request-then-respond
  # flow.
  class BulkPrintRunsController < BaseController
    include EventScoped
    before_action :set_bulk_print_run, only: :show

    def new
      @bulk_print_run = @event.bulk_print_runs.build
      authorize @bulk_print_run
      @print_stations = @event.print_stations.select(&:online?)
    end

    def create
      @bulk_print_run = @event.bulk_print_runs.build(bulk_print_run_params.merge(created_by: current_user))
      authorize @bulk_print_run

      if @bulk_print_run.save
        BulkPrintRunJob.perform_later(@bulk_print_run.id)
        redirect_to admin_event_bulk_print_run_path(@event, @bulk_print_run)
      else
        @print_stations = @event.print_stations.select(&:online?)
        render :new, status: :unprocessable_content
      end
    end

    def show
      authorize @bulk_print_run
    end

    private

    def set_bulk_print_run
      @bulk_print_run = @event.bulk_print_runs.find(params[:id])
    end

    def bulk_print_run_params
      params.require(:bulk_print_run).permit(:print_station_id, :limit)
    end
  end
end
