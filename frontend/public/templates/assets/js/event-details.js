document.addEventListener("DOMContentLoaded", () => {
    "use strict";

    // slider
    new Swiper(".et-event-details-ticket-time-slider", {
        slidesPerView: "auto",
        spaceBetween: 11,
        navigation: {
            prevEl: "#et-event-details-ticket-time-slider-nav .prev",
            nextEl: "#et-event-details-ticket-time-slider-nav .next",
        }
    });

    // ticket quantiy
    const decreaseButton = document.getElementById("decreaseButton");
    const increaseButton = document.getElementById("increaseButton");
    const ticketNumberElement = document.getElementById("ticketNumber");
    let ticketNumber = parseInt(ticketNumberElement.textContent);

    // Function to decrease ticket number
    decreaseButton.addEventListener("click", function () {
        if (ticketNumber > 1) {
            ticketNumber--;
            ticketNumberElement.textContent = ticketNumber;
        }
    });

    // Function to increase ticket number
    increaseButton.addEventListener("click", function () {
        ticketNumber++;
        ticketNumberElement.textContent = ticketNumber;
    });
});