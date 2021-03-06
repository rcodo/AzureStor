# custom progress bar with externally computed start and end values
# necessary to handle chunked transfers properly
storage_progress_bar <- R6::R6Class("storage_progress_bar",

public=list(

    display=NULL,
    bar=NULL,
    direction=NULL,
    offset=NULL,

    initialize=function(size, direction)
    {
        self$display <- isTRUE(getOption("azure_storage_progress_bar")) && interactive()
        if(self$display && size > 0)
        {
            self$direction <- direction
            self$offset <- 0
            self$bar <- utils::txtProgressBar(min=0, max=size, style=3)
        }
    },

    update=function()
    {
        if(!self$display || is.null(self$bar)) return(NULL)

        func <- function(down, up)
        {
            now <- self$offset + if(self$direction == "down") down[[2]] else up[[2]]
            utils::setTxtProgressBar(self$bar, now)
            TRUE
        }

        # hack b/c request function is not exported by httr
        req <- list(method=NULL, url=NULL, headers=NULL, fields=NULL,
                    options=list(noprogress=FALSE, progressfunction=func))
        structure(req, class="request")
    },

    close=function()
    {
        if(self$display && !is.null(self$bar)) close(self$bar)
    }
))
