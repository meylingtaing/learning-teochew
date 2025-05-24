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
    $('#dark-mode-toggle').click(function(e) {
        e.preventDefault();
        if (localStorage.getItem('darkMode') == '1') {
            localStorage.setItem('darkMode', '0');
            set_light();
        }
        else {
            localStorage.setItem('darkMode', '1');
            set_dark();
        }
    });
});
