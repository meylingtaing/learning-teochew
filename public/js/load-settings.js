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

        if ($(this).val() == 'traditional') {
            document.cookie = "simptrad=traditional; max-age=2592000; path=/";
            use_traditional = true;
        }
        else {
            document.cookie = "simptrad=simplified; max-age=2592000; path=/";
            use_traditional = false;
        }
    });
});
