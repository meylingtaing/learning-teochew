function set_dark() {
    $('html').addClass('dark-mode');
    $(function() {
        $('.dropdown-menu').addClass('bg-secondary');
    });
}

function set_light() {
    $('html').removeClass('dark-mode');
    $(function() {
        $('.dropdown-menu').removeClass('bg-secondary');
    });
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
