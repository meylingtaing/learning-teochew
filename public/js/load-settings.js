// Stuff for dark mode
function set_dark() {
    $('html').attr('data-bs-theme', 'dark');
    $('html').addClass('dark-mode');
}

function set_light() {
    $('html').attr('data-bs-theme', 'light');
    $('html').removeClass('dark-mode');
}

if (localStorage.getItem('darkMode') == '1') {
    set_dark();
}

$(function() {

    // Make sure the correct radio button (Dark mode/Light mode) is selected
    // by default
    if (localStorage.getItem('darkMode') == '1') {
        $('#dark-mode-input').prop('checked', true);
    }
    else {
        $('#light-mode-input').prop('checked', true);
    }

    // Toggle dark/light mode when the user changes the setting
    $('input[name=display-mode]').on("change", function(e) {
        e.preventDefault();

        if ($(this).val() == 'light-mode') {
            localStorage.setItem('darkMode', '0');
            set_light();
        }
        else {
            localStorage.setItem('darkMode', '1');
            set_dark();
        }
    });

    // Toggle traditional/simplified characters when user changes the setting
    $('input[name=chinese-character-setting]').on("change", function(e) {
        e.preventDefault();

        // Set all the Chinese characters to be traditional
        if ($(this).val() == 'traditional') {
            $('.chinese').html(function() {
                const traditional_chars = $(this).attr('data-traditional');
                if (traditional_chars) {
                    return traditional_chars;
                }
            });

            // But there's one edge case, where we show the opposite in "More
            // Details", so handle that case specifically here
            $('.traditional').addClass('simplified').removeClass('traditional')
                .text(function() {
                    return "Simplified: " + $(this).attr('data-simplified');
                });

            document.cookie = "simptrad=traditional; max-age=2592000; path=/";
            use_traditional = true;
        }
        else {
            $('.chinese').html(function() {
                const simplified_chars = $(this).attr('data-simplified');
                if (simplified_chars) {
                    return simplified_chars;
                }
            });

            $('.simplified').addClass('traditional').removeClass('simplified')
                .text(function() {
                    return "Traditional: " + $(this).attr('data-traditional');
                });

            document.cookie = "simptrad=simplified; max-age=2592000; path=/";
            use_traditional = false;
        }
    });
});
